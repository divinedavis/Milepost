import CoreLocation
import Foundation
import Supabase

/// Everything the friends layer needs from a server. The app talks to
/// Supabase; UI tests get an in-memory stand-in (`-uitest-social-demo`),
/// because a runner-launched app cannot keep a real session (no keychain)
/// and Sign in with Apple is a system sheet XCUITest cannot drive.
@MainActor
protocol SocialBackend: AnyObject {
    var isConfigured: Bool { get }
    /// A synchronous read of the stored session, so a signed-in cold start
    /// never draws the signed-out state first.
    var sessionUserID: UUID? { get }
    /// The signed-in user id after every auth change; nil when signed out.
    func sessionChanges() -> AsyncStream<UUID?>
    /// The signed-in account as the auth server described it (creation and
    /// last sign-in time, whether it passed the age question), for deciding
    /// whether a Sign in with Apple just created it.
    var sessionAccount: SessionAccount? { get }

    func signInWithApple(idToken: String, nonce: String?) async throws
    /// Marks the signed-in account `age_confirmed_13_plus = true` in its auth
    /// user_metadata. The birth date itself is never sent.
    func confirmAge() async throws
    func signOut() async
    func deleteAccount() async throws

    func profile(id: UUID) async throws -> FriendProfile?
    func createProfile(id: UUID, username: String, displayName: String) async throws

    func search(_ query: String) async throws -> [FriendProfile]
    func connections() async throws -> [FriendProfile]
    func blocked() async throws -> [FriendProfile]
    func sendRequest(to id: UUID) async throws -> FriendStatus
    func respond(to id: UUID, accept: Bool) async throws
    func remove(_ id: UUID) async throws
    func block(_ id: UUID) async throws
    func unblock(_ id: UUID) async throws
    func report(_ id: UUID, activityID: UUID?, reason: String) async throws

    func feed(before: Date?) async throws -> [FeedActivity]
    func upsert(_ rows: [SharedActivityPayload]) async throws
    func deleteShared(ids: [UUID], owner: UUID) async throws
    func deleteAllShared(owner: UUID) async throws

    func upsertStreets(_ rows: [SharedStreetsPayload]) async throws
    func deleteAllStreets(owner: UUID) async throws
    /// Friends' street cells from activities since `since` (nil = all time).
    func friendStreets(since: Date?) async throws -> [FriendStreets]
}

enum Secrets {
    private static func plist(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    static var supabaseHost: String { plist("SUPABASE_HOST") }
    static var supabaseAnonKey: String { plist("SUPABASE_ANON_KEY") }
    /// False in a build without Secrets.xcconfig — the Friends feed then
    /// says so instead of failing on every request.
    static var isConfigured: Bool {
        !supabaseHost.isEmpty && !supabaseAnonKey.isEmpty && !supabaseHost.contains("$(")
    }
}

/// XCUITest-launched processes cannot write the keychain, so under `-uitest`
/// the session lives in memory (and a real sign-in is impossible anyway).
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        store[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[key] = nil
    }
}

@MainActor
final class SupabaseSocialBackend: SocialBackend {
    let isConfigured = Secrets.isConfigured
    private let client: SupabaseClient

    init(inMemorySession: Bool) {
        let host = Secrets.isConfigured ? URL(string: "https://\(Secrets.supabaseHost)")! : URL(string: "https://unconfigured.invalid")!
        let key = Secrets.isConfigured ? Secrets.supabaseAnonKey : "unconfigured"
        client = SupabaseClient(
            supabaseURL: host,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: inMemorySession ? InMemoryAuthStorage() : KeychainLocalStorage(),
                    // Emit the stored session at once instead of after a token
                    // refresh round trip (the SDK's default), which otherwise
                    // shows a signed-in user the sign-in card on cold start.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    var sessionUserID: UUID? {
        isConfigured ? client.auth.currentSession?.user.id : nil
    }

    func sessionChanges() -> AsyncStream<UUID?> {
        guard isConfigured else { return AsyncStream { $0.finish() } }
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in auth.authStateChanges {
                    switch event {
                    case .initialSession:
                        continuation.yield(session?.user.id)
                    case .signedIn, .tokenRefreshed, .userUpdated:
                        if let session { continuation.yield(session.user.id) }
                    case .signedOut, .userDeleted:
                        continuation.yield(nil)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    var sessionAccount: SessionAccount? {
        guard isConfigured, let user = client.auth.currentSession?.user else { return nil }
        return SessionAccount(id: user.id, createdAt: user.createdAt, lastSignInAt: user.lastSignInAt,
                              ageConfirmed: user.userMetadata[AgeGate.metadataKey]?.boolValue == true)
    }

    func signInWithApple(idToken: String, nonce: String?) async throws {
        guard isConfigured else { throw SocialError.notConfigured }
        try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }

    func confirmAge() async throws {
        guard isConfigured else { throw SocialError.notConfigured }
        _ = try await client.auth.update(user: UserAttributes(data: [AgeGate.metadataKey: .bool(true)]))
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    /// App Store 5.1.1(v). There is no Storage bucket, so the RPC's
    /// auth.users cascade is the whole job.
    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
        try? await client.auth.signOut()
    }

    func profile(id: UUID) async throws -> FriendProfile? {
        let rows: [FriendProfile] = try await client.from("profiles")
            .select("id,username,display_name")
            .eq("id", value: id)
            .limit(1)
            .execute().value
        return rows.first
    }

    func createProfile(id: UUID, username: String, displayName: String) async throws {
        struct Insert: Encodable {
            let id: UUID
            let username: String
            let display_name: String
        }
        try await client.from("profiles")
            .insert(Insert(id: id, username: username, display_name: displayName), returning: .minimal)
            .execute()
    }

    func search(_ query: String) async throws -> [FriendProfile] {
        struct Params: Encodable { let q: String }
        return try await client.rpc("search_profiles", params: Params(q: query)).execute().value
    }

    func connections() async throws -> [FriendProfile] {
        try await client.rpc("list_connections").execute().value
    }

    func blocked() async throws -> [FriendProfile] {
        try await client.rpc("list_blocked").execute().value
    }

    func sendRequest(to id: UUID) async throws -> FriendStatus {
        struct Params: Encodable { let target: UUID }
        let raw: String = try await client.rpc("send_friend_request", params: Params(target: id)).execute().value
        return FriendStatus(rawValue: raw) ?? .outgoing
    }

    func respond(to id: UUID, accept: Bool) async throws {
        struct Params: Encodable { let requester: UUID; let accept: Bool }
        try await client.rpc("respond_friend_request", params: Params(requester: id, accept: accept)).execute()
    }

    func remove(_ id: UUID) async throws {
        struct Params: Encodable { let other: UUID }
        try await client.rpc("remove_friend", params: Params(other: id)).execute()
    }

    func block(_ id: UUID) async throws {
        struct Params: Encodable { let target: UUID }
        try await client.rpc("block_user", params: Params(target: id)).execute()
    }

    func unblock(_ id: UUID) async throws {
        try await client.from("blocks").delete().eq("blocked_id", value: id).execute()
    }

    func report(_ id: UUID, activityID: UUID?, reason: String) async throws {
        struct Insert: Encodable { let target_id: UUID; let activity_id: UUID?; let reason: String }
        try await client.from("reports")
            .insert(Insert(target_id: id, activity_id: activityID, reason: reason), returning: .minimal)
            .execute()
    }

    func feed(before: Date?) async throws -> [FeedActivity] {
        struct Params: Encodable { let before_ts: String?; let max_rows: Int }
        return try await client.rpc("friend_feed", params: Params(before_ts: before.map(SocialDates.format), max_rows: 50))
            .execute().value
    }

    func upsert(_ rows: [SharedActivityPayload]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("shared_activities")
            .upsert(rows, onConflict: "user_id,id", returning: .minimal)
            .execute()
    }

    func deleteShared(ids: [UUID], owner: UUID) async throws {
        guard !ids.isEmpty else { return }
        try await client.from("shared_activities")
            .delete()
            .eq("user_id", value: owner)
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    func deleteAllShared(owner: UUID) async throws {
        try await client.from("shared_activities").delete().eq("user_id", value: owner).execute()
    }

    func upsertStreets(_ rows: [SharedStreetsPayload]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("shared_streets")
            .upsert(rows, onConflict: "user_id,activity_id", returning: .minimal)
            .execute()
    }

    func deleteAllStreets(owner: UUID) async throws {
        try await client.from("shared_streets").delete().eq("user_id", value: owner).execute()
    }

    func friendStreets(since: Date?) async throws -> [FriendStreets] {
        struct Params: Encodable { let since_ts: String?; let max_rows: Int }
        return try await client.rpc("friend_streets", params: Params(since_ts: since.map(SocialDates.format), max_rows: 300))
            .execute().value
    }
}

#if DEBUG
/// In-memory friends for UI tests and unit tests: you (`you_demo`), a friend
/// with two activities, an incoming request, and a stranger to find.
@MainActor
final class DemoSocialBackend: SocialBackend {
    static let me = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let jamie = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let sam = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let jordan = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    let isConfigured = true
    private(set) var sessionUserID: UUID? = DemoSocialBackend.me
    /// The demo account: an old, existing one unless a test makes it new.
    var sessionAccount: SessionAccount? {
        guard let id = sessionUserID else { return nil }
        return SessionAccount(id: id, createdAt: accountCreated, lastSignInAt: lastSignIn, ageConfirmed: ageConfirmed)
    }
    private var accountCreated = Date(timeIntervalSince1970: 1_757_000_000)
    private var lastSignIn: Date? = .now
    private(set) var ageConfirmed = false
    /// Accounts deleted (by the user, or discarded by the age gate).
    private(set) var deletedAccounts = 0
    /// The next `signInWithApple` creates a brand-new account (Apple's sheet
    /// cannot be driven by tests, so the outcome is chosen here).
    var nextSignInCreatesAccount = false
    private var continuation: AsyncStream<UUID?>.Continuation?
    private var people: [FriendProfile] = [
        FriendProfile(id: jamie, username: "jamie_runs", displayName: "Jamie", status: .friend),
        FriendProfile(id: sam, username: "sam_walks", displayName: "Sam", status: .incoming),
        FriendProfile(id: jordan, username: "jordan_rides", displayName: "Jordan", status: .none),
    ]
    private var blockedIDs: Set<UUID> = []
    private var activities: [FeedActivity]
    private(set) var shared: [UUID: SharedActivityPayload] = [:]
    private(set) var reports: [String] = []

    init(now: Date = .now) {
        func act(_ user: FriendProfile, _ title: String, _ sport: Sport, hoursAgo: Double, meters: Double, seconds: Double) -> FeedActivity {
            FeedActivity(userID: user.id, activityID: UUID(), sport: sport, title: title,
                         startDate: now.addingTimeInterval(-hoursAgo * 3600), distanceMeters: meters,
                         movingSeconds: seconds, username: user.username, displayName: user.displayName)
        }
        let p = people
        activities = [
            act(p[0], "Lunch Loop", .run, hoursAgo: 3, meters: 5200, seconds: 1560),
            act(p[0], "Hill Repeats", .run, hoursAgo: 27, meters: 8100, seconds: 2700),
            act(p[1], "Evening Walk", .walk, hoursAgo: 6, meters: 3200, seconds: 2400),
            act(p[2], "Bridge Ride", .bike, hoursAgo: 30, meters: 24000, seconds: 3600),
        ]
    }

    func sessionChanges() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Starts with no session (a phone that has never signed in).
    func startSignedOut() { sessionUserID = nil }

    /// Starts signed in to an account created moments ago that has not
    /// answered the age question: the state a first Sign in with Apple leaves.
    func startWithNewAccount() {
        sessionUserID = Self.me
        accountCreated = .now
        lastSignIn = .now
        ageConfirmed = false
    }

    func signInWithApple(idToken: String, nonce: String?) async throws {
        if nextSignInCreatesAccount {
            startWithNewAccount()
        } else {
            lastSignIn = .now
        }
        sessionUserID = Self.me
        continuation?.yield(Self.me)
    }

    func confirmAge() async throws {
        guard sessionUserID != nil else { throw SocialError.notConfigured }
        ageConfirmed = true
    }

    func signOut() async {
        sessionUserID = nil
        continuation?.yield(nil)
    }

    func deleteAccount() async throws {
        deletedAccounts += 1
        ageConfirmed = false
        await signOut()
    }

    func profile(id: UUID) async throws -> FriendProfile? {
        id == Self.me ? FriendProfile(id: Self.me, username: "you_demo", displayName: "You") : nil
    }

    func createProfile(id: UUID, username: String, displayName: String) async throws {}

    private func visible(_ p: FriendProfile) -> Bool { !blockedIDs.contains(p.id) }

    func search(_ query: String) async throws -> [FriendProfile] {
        let q = query.lowercased()
        guard q.count >= 3 else { return [] }
        return people.filter { visible($0) && $0.username.hasPrefix(q) }
    }

    func connections() async throws -> [FriendProfile] {
        people.filter { visible($0) && $0.status != .none }
    }

    func blocked() async throws -> [FriendProfile] {
        people.filter { blockedIDs.contains($0.id) }.map { FriendProfile(id: $0.id, username: $0.username, displayName: $0.displayName) }
    }

    private func setStatus(_ id: UUID, _ status: FriendStatus) {
        if let i = people.firstIndex(where: { $0.id == id }) { people[i].status = status }
    }

    func sendRequest(to id: UUID) async throws -> FriendStatus {
        let current = people.first { $0.id == id }?.status ?? .none
        let next: FriendStatus = current == .incoming || current == .friend ? .friend : .outgoing
        setStatus(id, next)
        return next
    }

    func respond(to id: UUID, accept: Bool) async throws { setStatus(id, accept ? .friend : .none) }
    func remove(_ id: UUID) async throws { setStatus(id, .none) }

    func block(_ id: UUID) async throws {
        blockedIDs.insert(id)
        setStatus(id, .none)
    }

    func unblock(_ id: UUID) async throws { blockedIDs.remove(id) }

    func report(_ id: UUID, activityID: UUID?, reason: String) async throws { reports.append(reason) }

    func feed(before: Date?) async throws -> [FeedActivity] {
        let friendIDs = Set(people.filter { $0.status == .friend && visible($0) }.map(\.id))
        return activities.filter { friendIDs.contains($0.userID) }.sorted { $0.startDate > $1.startDate }
    }

    func upsert(_ rows: [SharedActivityPayload]) async throws {
        for r in rows { shared[r.id] = r }
    }

    func deleteShared(ids: [UUID], owner: UUID) async throws {
        for id in ids { shared[id] = nil }
    }

    func deleteAllShared(owner: UUID) async throws {
        shared = [:]
        sharedStreets = [:]
    }

    private(set) var sharedStreets: [UUID: SharedStreetsPayload] = [:]

    func upsertStreets(_ rows: [SharedStreetsPayload]) async throws {
        for r in rows { sharedStreets[r.activity_id] = r }
    }

    func deleteAllStreets(owner: UUID) async throws { sharedStreets = [:] }

    /// Jamie's walk near the UI tests' pinned fix: up Vanderbilt Ave (where
    /// the seeded heatmap walks go too, so it turns green) and on west along
    /// a street only Jamie has covered (blue).
    func friendStreets(since: Date?) async throws -> [FriendStreets] {
        guard people.contains(where: { $0.id == Self.jamie && $0.status == .friend && visible($0) }) else { return [] }
        // A fix every ~8 m, as a real walk records: corners alone are more
        // than `gapMeters` apart and would rightly not be joined.
        let corners = [(40.6835, -73.9680), (40.6880, -73.9690), (40.6890, -73.9760)]
        var walk: [CLLocationCoordinate2D] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            for i in 0..<60 {
                let t = Double(i) / 60
                walk.append(CLLocationCoordinate2D(latitude: a.0 + (b.0 - a.0) * t, longitude: a.1 + (b.1 - a.1) * t))
            }
        }
        walk.append(CLLocationCoordinate2D(latitude: 40.6890, longitude: -73.9760))
        // Sorted, as the server stores them: the map rebuilds the lines.
        let cells = Set(RouteHeatmap.orderedCells(walk)).map(RouteHeatmap.pack).sorted()
        return [FriendStreets(userID: Self.jamie, activityID: UUID(), cells: cells)]
    }
}
#endif
