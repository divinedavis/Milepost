import AuthenticationServices
import Foundation
import Observation

/// Signed-in state, friends and the friends feed. Three auth states on
/// purpose: nothing known yet, signed out, signed in (with or without a
/// username).
@MainActor
@Observable
final class SocialStore {
    enum Phase: Equatable {
        case restoring, signedOut, signedIn
    }

    /// On by default: signing in to add friends is the opt-in. Turning it off
    /// deletes every row this account has shared.
    static let shareKey = "social.shareActivities"
    /// Local deletes that could not reach the server yet.
    static let pendingDeletesKey = "social.pendingDeletes"

    private(set) var phase: Phase = .restoring
    private(set) var userID: UUID?
    private(set) var profile: FriendProfile?
    private(set) var profileLoaded = false
    private(set) var profileError: String?
    private(set) var feed: [FeedActivity] = []
    private(set) var feedLoaded = false
    private(set) var feedError: String?
    private(set) var connections: [FriendProfile] = []
    private(set) var blocked: [FriendProfile] = []
    var lastError: String?
    /// A one-line confirmation or failure the current screen shows in an alert.
    var notice: String?
    /// Apple sends the name exactly once; kept for the username sheet.
    var suggestedDisplayName = ""

    /// The phone's saved activities, supplied by the app (the store has no
    /// model context of its own).
    var localActivities: () -> [Activity] = { [] }

    let isAvailable: Bool
    private let backend: SocialBackend
    private let defaults: UserDefaults
    private var pendingAppleNonce: String?
    private var listener: Task<Void, Never>?

    var canUseFriends: Bool { phase == .signedIn && profile != nil }
    var sharingEnabled: Bool { defaults.object(forKey: Self.shareKey) as? Bool ?? true }
    var incoming: [FriendProfile] { connections.filter { $0.status == .incoming } }
    var outgoing: [FriendProfile] { connections.filter { $0.status == .outgoing } }
    var friends: [FriendProfile] { connections.filter { $0.status == .friend } }

    init(backend: SocialBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        isAvailable = backend.isConfigured
        if let id = backend.sessionUserID {
            apply(id)
        } else {
            phase = .signedOut
        }
        let stream = backend.sessionChanges()
        listener = Task { [weak self] in
            for await id in stream {
                self?.apply(id)
            }
        }
    }

    private func apply(_ id: UUID?) {
        guard let id else {
            reset()
            return
        }
        let changed = id != userID
        userID = id
        phase = .signedIn
        if changed {
            profile = nil
            profileLoaded = false
            Task { await loadProfile() }
        }
    }

    private func reset() {
        userID = nil
        profile = nil
        profileLoaded = false
        profileError = nil
        feed = []
        feedLoaded = false
        connections = []
        blocked = []
        phase = .signedOut
    }

    // MARK: Profile

    func loadProfile() async {
        guard let id = userID else { return }
        do {
            profile = try await backend.profile(id: id)
            profileError = nil
            profileLoaded = true
            if profile != nil { await profileReady() }
        } catch {
            // Offline is not "has no username": keep asking rather than
            // offering to create a second one.
            profileError = error.localizedDescription
        }
    }

    private func profileReady() async {
        await flushPendingDeletes()
        await syncAll()
        await loadConnections()
    }

    func isUsernameAvailable(_ username: String) async -> Bool {
        guard Username.isValid(username) else { return false }
        guard let hits = try? await backend.search(username) else { return true }
        return !hits.contains { $0.username == username }
    }

    func createProfile(username: String, displayName: String) async throws {
        guard let id = userID else { return }
        try await backend.createProfile(id: id, username: username, displayName: displayName)
        profile = try await backend.profile(id: id)
        profileLoaded = true
        if profile != nil { await profileReady() }
    }

    // MARK: Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AuthNonce.random()
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = AuthNonce.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        let nonce = pendingAppleNonce
        pendingAppleNonce = nil
        lastError = nil
        do {
            let authorization: ASAuthorization
            do {
                authorization = try result.get()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // Apple's sheet also reports its own failures as a cancel; the
                // sheet has already shown them.
                return
            }
            guard let nonce else { throw SocialError.missingIdentityToken }
            let credential = try AppleCredential.from(authorization, rawNonce: nonce)
            // Apple does not always include the nonce claim, and GoTrue
            // rejects a nonce the token does not carry.
            let claim = IDToken.stringClaim("nonce", from: credential.idToken)
            try await backend.signInWithApple(idToken: credential.idToken, nonce: claim == nil ? nil : credential.rawNonce)
            if let name = credential.fullName {
                suggestedDisplayName = PersonNameComponentsFormatter().string(from: name)
            }
            apply(backend.sessionUserID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        await backend.signOut()
        reset()
    }

    func deleteAccount() async throws {
        try await backend.deleteAccount()
        defaults.removeObject(forKey: Self.pendingDeletesKey)
        reset()
    }

    // MARK: Sharing

    /// Uploads every local activity. An upsert, so repeating it is harmless;
    /// it runs whenever a session with a username starts, which is also what
    /// retries uploads that failed offline.
    func syncAll() async {
        guard let me = userID, profile != nil, sharingEnabled else { return }
        let rows = localActivities().compactMap { SharedActivityPayload(activity: $0, userID: me) }
        for start in stride(from: 0, to: rows.count, by: 200) {
            do {
                try await backend.upsert(Array(rows[start..<min(start + 200, rows.count)]))
            } catch {
                return
            }
        }
    }

    func share(_ activity: Activity) async {
        guard let me = userID, profile != nil, sharingEnabled,
              let row = SharedActivityPayload(activity: activity, userID: me) else { return }
        try? await backend.upsert([row])
    }

    /// Called after a local delete. A delete that cannot reach the server now
    /// is queued, or a friend would keep seeing an activity that is gone.
    func unshare(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        if let me = userID, profile != nil {
            do {
                try await backend.deleteShared(ids: ids, owner: me)
                return
            } catch {}
        }
        var pending = defaults.stringArray(forKey: Self.pendingDeletesKey) ?? []
        pending.append(contentsOf: ids.map(\.uuidString))
        defaults.set(Array(pending.suffix(500)), forKey: Self.pendingDeletesKey)
    }

    private func flushPendingDeletes() async {
        guard let me = userID else { return }
        let pending = (defaults.stringArray(forKey: Self.pendingDeletesKey) ?? []).compactMap(UUID.init(uuidString:))
        guard !pending.isEmpty else { return }
        if (try? await backend.deleteShared(ids: pending, owner: me)) != nil {
            defaults.removeObject(forKey: Self.pendingDeletesKey)
        }
    }

    func sharingChanged(to on: Bool) async {
        guard let me = userID, profile != nil else { return }
        if on {
            await syncAll()
        } else {
            do {
                try await backend.deleteAllShared(owner: me)
            } catch {
                defaults.set(true, forKey: Self.shareKey)
                notice = "Couldn't stop sharing: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Friends

    func loadFeed() async {
        guard canUseFriends else { return }
        do {
            feed = try await backend.feed(before: nil)
            feedError = nil
        } catch {
            feedError = error.localizedDescription
        }
        feedLoaded = true
    }

    func loadConnections() async {
        guard canUseFriends else { return }
        do {
            connections = try await backend.connections()
            blocked = try await backend.blocked()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func search(_ query: String) async -> [FriendProfile] {
        do {
            return try await backend.search(query)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    @discardableResult
    func sendRequest(to id: UUID) async -> FriendStatus? {
        do {
            let status = try await backend.sendRequest(to: id)
            await loadConnections()
            if status == .friend { await loadFeed() }
            return status
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    func respond(to id: UUID, accept: Bool) async {
        await run { try await self.backend.respond(to: id, accept: accept) }
    }

    func remove(_ id: UUID) async {
        await run { try await self.backend.remove(id) }
    }

    func block(_ id: UUID) async {
        await run { try await self.backend.block(id) }
    }

    func unblock(_ id: UUID) async {
        await run { try await self.backend.unblock(id) }
    }

    func report(_ id: UUID, activityID: UUID?, reason: ReportReason) async {
        do {
            try await backend.report(id, activityID: activityID, reason: reason.rawValue)
            notice = "Reported. Thanks for telling us."
        } catch {
            notice = error.localizedDescription
        }
    }

    /// A friendship change moves both lists and the feed.
    private func run(_ change: () async throws -> Void) async {
        do {
            try await change()
        } catch {
            notice = error.localizedDescription
        }
        await loadConnections()
        await loadFeed()
    }
}
