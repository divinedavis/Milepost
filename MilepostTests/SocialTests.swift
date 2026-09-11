import XCTest
@testable import Milepost

@MainActor
final class SocialTests: XCTestCase {

    // MARK: Usernames

    func testUsernameRulesMatchTheServerCheck() {
        XCTAssertTrue(Username.isValid("jamie_runs"))
        XCTAssertTrue(Username.isValid("abc"))
        XCTAssertFalse(Username.isValid("ab"), "3 minimum")
        XCTAssertFalse(Username.isValid(String(repeating: "a", count: 21)), "20 maximum")
        XCTAssertFalse(Username.isValid("Jamie"), "lowercase only")
        XCTAssertFalse(Username.isValid("jamie.runs"))
    }

    func testNormalizeKeepsOnlyWhatTheServerAccepts() {
        XCTAssertEqual(Username.normalize("Jamie Runs!"), "jamieruns")
        XCTAssertEqual(Username.normalize("José_1"), "jos_1", "non-ASCII letters are dropped, not transliterated")
        XCTAssertEqual(Username.normalize(String(repeating: "x", count: 30)).count, 20)
    }

    // MARK: Sign in with Apple

    func testNonceDigestIsHexSHA256() {
        XCTAssertEqual(AuthNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(AuthNonce.random().count, 32)
        XCTAssertNotEqual(AuthNonce.random(), AuthNonce.random())
    }

    private func token(_ json: String) -> String {
        let b64 = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "header.\(b64).signature"
    }

    /// base64url drops padding; every length has to decode or a present
    /// claim reads as absent and the nonce is silently not sent.
    func testIDTokenClaimDecodesEveryPaddingLength() {
        for value in ["a", "ab", "abc", "abcd"] {
            XCTAssertEqual(IDToken.stringClaim("nonce", from: token(#"{"nonce":"\#(value)"}"#)), value)
        }
        XCTAssertNil(IDToken.stringClaim("nonce", from: token(#"{"sub":"x"}"#)))
        XCTAssertNil(IDToken.stringClaim("nonce", from: "not-a-jwt"))
    }

    // MARK: What leaves the phone

    private func activity(title: String = "Evening Ride", meters: Double = 12_000, seconds: Double = 1_800) -> Activity {
        Activity(title: title,
                 startDate: Date(timeIntervalSince1970: 1_757_500_000),
                 endDate: Date(timeIntervalSince1970: 1_757_502_000),
                 movingSeconds: seconds,
                 distanceMeters: meters,
                 splitMeters: DistanceUnit.miles.meters,
                 route: [],
                 splits: [],
                 sport: .bike)
    }

    func testSharedPayloadIsStatsOnly() throws {
        let a = activity(title: "  Evening Ride ")
        let me = UUID()
        let payload = try XCTUnwrap(SharedActivityPayload(activity: a, userID: me))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["user_id", "id", "sport", "title", "start_date", "distance_m", "moving_s"],
                       "a route, split or coordinate key here would leak where someone lives")
        XCTAssertEqual(payload.sport, "bike", "must match the table's sport check")
        XCTAssertEqual(payload.title, "Evening Ride")
        XCTAssertEqual(payload.id, a.id)
        XCTAssertEqual(payload.user_id, me)
        XCTAssertEqual(payload.start_date, "2025-09-10T10:26:40Z")
    }

    func testPayloadTitleFallsBackAndIsCapped() throws {
        let blank = try XCTUnwrap(SharedActivityPayload(activity: activity(title: "   "), userID: UUID()))
        XCTAssertFalse(blank.title.isEmpty, "the table refuses an empty title")
        let long = try XCTUnwrap(SharedActivityPayload(activity: activity(title: String(repeating: "x", count: 200)), userID: UUID()))
        XCTAssertEqual(long.title.count, SharedActivityPayload.maxTitle)
    }

    func testPayloadRefusesRowsTheTableWouldReject() {
        XCTAssertNil(SharedActivityPayload(activity: activity(meters: 2_000_000), userID: UUID()))
        XCTAssertNil(SharedActivityPayload(activity: activity(seconds: 700_000), userID: UUID()))
        XCTAssertNil(SharedActivityPayload(activity: activity(meters: .nan), userID: UUID()))
    }

    // MARK: Reading the server

    func testFeedRowDecodesPostgrestTimestamps() throws {
        let json = """
        [{"user_id":"08EB93DE-883B-4F3C-AB4A-E92E1E0AF5A3","id":"E12E0207-F588-433E-8C48-0C06FAADD50C","sport":"bike",
          "title":"Bridge Ride","start_date":"2026-09-10T11:00:00.12345+00:00","distance_m":24000,"moving_s":3600,
          "username":"jordan_rides","display_name":""},
         {"user_id":"08EB93DE-883B-4F3C-AB4A-E92E1E0AF5A3","id":"E12E0207-F588-433E-8C48-0C06FAADD50D","sport":"swim",
          "title":"Mystery","start_date":"2026-09-10T11:00:00+00:00","distance_m":1,"moving_s":1,
          "username":"jordan_rides","display_name":"Jordan"}]
        """
        let rows = try JSONDecoder().decode([FeedActivity].self, from: Data(json.utf8))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].sport, .bike)
        XCTAssertEqual(rows[0].startDate, SocialDates.parse("2026-09-10T11:00:00Z"))
        XCTAssertEqual(rows[0].name, "@jordan_rides", "no display name falls back to the handle")
        XCTAssertEqual(rows[1].sport, .run, "an unknown sport still renders")
        XCTAssertEqual(rows[1].name, "Jordan")
    }

    func testSocialDatesAcceptEveryFractionLength() {
        let whole = SocialDates.parse("2026-09-10T11:00:00Z")
        XCTAssertNotNil(whole)
        for s in ["2026-09-10T11:00:00.1+00:00", "2026-09-10T11:00:00.123+00:00", "2026-09-10T11:00:00.123456+00:00"] {
            XCTAssertEqual(SocialDates.parse(s), whole, s)
        }
    }

    func testProfileDecodesWithAndWithoutStatus() throws {
        let rows = try JSONDecoder().decode([FriendProfile].self, from: Data("""
        [{"id":"08EB93DE-883B-4F3C-AB4A-E92E1E0AF5A3","username":"a_b","display_name":"A"},
         {"id":"08EB93DE-883B-4F3C-AB4A-E92E1E0AF5A4","username":"c_d","display_name":"","status":"incoming"},
         {"id":"08EB93DE-883B-4F3C-AB4A-E92E1E0AF5A5","username":"e_f","status":"weird"}]
        """.utf8))
        XCTAssertEqual(rows.map(\.status), [.none, .incoming, .none])
    }

    // MARK: The store, against the in-memory backend

    private func store() -> (SocialStore, DemoSocialBackend, UserDefaults) {
        let suite = "SocialTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let backend = DemoSocialBackend()
        return (SocialStore(backend: backend, defaults: defaults), backend, defaults)
    }

    func testStartsSignedInFromTheStoredSessionWithoutWaiting() {
        let (s, _, _) = store()
        XCTAssertEqual(s.phase, .signedIn, "a signed-in cold start must not pass through signed-out")
    }

    func testFriendFlows() async {
        let (s, _, _) = store()
        await s.loadProfile()
        XCTAssertEqual(s.profile?.username, "you_demo")
        XCTAssertEqual(s.incoming.map(\.username), ["sam_walks"])
        XCTAssertEqual(s.friends.map(\.username), ["jamie_runs"])

        await s.loadFeed()
        XCTAssertEqual(Set(s.feed.map(\.username)), ["jamie_runs"], "only friends' activities")

        let status = await s.sendRequest(to: DemoSocialBackend.jordan)
        XCTAssertEqual(status, .outgoing)
        XCTAssertEqual(s.outgoing.map(\.username), ["jordan_rides"])

        await s.respond(to: DemoSocialBackend.sam, accept: true)
        XCTAssertEqual(Set(s.friends.map(\.username)), ["jamie_runs", "sam_walks"])
        XCTAssertTrue(s.feed.contains { $0.username == "sam_walks" }, "accepting brings their activities in")

        await s.block(DemoSocialBackend.jamie)
        XCTAssertFalse(s.feed.contains { $0.username == "jamie_runs" })
        XCTAssertEqual(s.blocked.map(\.username), ["jamie_runs"])
        let hits = await s.search("ja")
        XCTAssertTrue(hits.isEmpty, "a blocked person does not come back in search")
    }

    func testSharingUploadsDeletesAndStops() async throws {
        let (s, backend, defaults) = store()
        let a = activity()
        s.localActivities = { [a] }
        await s.loadProfile()
        XCTAssertNotNil(backend.shared[a.id], "a new session uploads the phone's activities")

        await s.unshare([a.id])
        XCTAssertNil(backend.shared[a.id])

        await s.share(a)
        XCTAssertNotNil(backend.shared[a.id])
        defaults.set(false, forKey: SocialStore.shareKey)
        await s.sharingChanged(to: false)
        XCTAssertTrue(backend.shared.isEmpty, "turning sharing off deletes what was shared")
        await s.share(a)
        XCTAssertTrue(backend.shared.isEmpty, "and nothing new goes up while it is off")
    }

    func testSignOutClearsEverything() async {
        let (s, _, _) = store()
        await s.loadProfile()
        await s.loadFeed()
        await s.signOut()
        XCTAssertEqual(s.phase, .signedOut)
        XCTAssertNil(s.profile)
        XCTAssertTrue(s.feed.isEmpty)
        XCTAssertTrue(s.connections.isEmpty)
    }
}
