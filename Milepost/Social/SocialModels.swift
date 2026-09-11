import Foundation

/// Where the caller stands with another person, as the server reports it.
enum FriendStatus: String, Codable {
    case none, outgoing, incoming, friend
}

/// Someone on Milepost: yourself, a friend, a request, or a search result.
struct FriendProfile: Identifiable, Hashable, Decodable {
    let id: UUID
    var username: String
    var displayName: String
    var status: FriendStatus

    enum CodingKeys: String, CodingKey {
        case id, username, status
        case displayName = "display_name"
    }

    init(id: UUID, username: String, displayName: String = "", status: FriendStatus = .none) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        // The profiles table has no status; an unknown value is no relationship.
        status = (try? c.decodeIfPresent(String.self, forKey: .status)).flatMap { FriendStatus(rawValue: $0) } ?? .none
    }

    var handle: String { "@\(username)" }
    var name: String { displayName.isEmpty ? handle : displayName }
}

/// The server enforces the same pattern (`profiles.username` check).
enum Username {
    static func isValid(_ s: String) -> Bool {
        s.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    /// What a text field may hold: lowercase ASCII letters, digits, underscore.
    static func normalize(_ s: String) -> String {
        String(s.lowercased().filter { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }.prefix(20))
    }
}

/// One friend's activity in the Block tab's Friends feed.
struct FeedActivity: Identifiable, Hashable, Decodable {
    let userID: UUID
    let activityID: UUID
    let sport: Sport
    let title: String
    let startDate: Date
    let distanceMeters: Double
    let movingSeconds: Double
    let username: String
    let displayName: String

    var id: String { "\(userID.uuidString)/\(activityID.uuidString)" }
    var handle: String { "@\(username)" }
    var name: String { displayName.isEmpty ? handle : displayName }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", activityID = "id", sport, title
        case startDate = "start_date", distanceMeters = "distance_m", movingSeconds = "moving_s"
        case username, displayName = "display_name"
    }

    init(userID: UUID, activityID: UUID, sport: Sport, title: String, startDate: Date,
         distanceMeters: Double, movingSeconds: Double, username: String, displayName: String) {
        self.userID = userID
        self.activityID = activityID
        self.sport = sport
        self.title = title
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.movingSeconds = movingSeconds
        self.username = username
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(UUID.self, forKey: .userID)
        activityID = try c.decode(UUID.self, forKey: .activityID)
        sport = Sport(rawValue: try c.decode(String.self, forKey: .sport)) ?? .run
        title = try c.decode(String.self, forKey: .title)
        let raw = try c.decode(String.self, forKey: .startDate)
        guard let date = SocialDates.parse(raw) else {
            throw DecodingError.dataCorruptedError(forKey: .startDate, in: c, debugDescription: "unreadable timestamp \(raw)")
        }
        startDate = date
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        movingSeconds = try c.decode(Double.self, forKey: .movingSeconds)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    }
}

/// What leaves the phone when an activity is shared: stats only. The route
/// and splits stay in the local store — where a run starts and ends is where
/// someone lives. Keys match `public.shared_activities`.
struct SharedActivityPayload: Encodable, Equatable {
    let user_id: UUID
    let id: UUID
    let sport: String
    let title: String
    let start_date: String
    let distance_m: Double
    let moving_s: Double

    static let maxTitle = 80

    /// Nil when the row would fail the table's checks and sink its batch.
    init?(activity: Activity, userID: UUID) {
        guard activity.distanceMeters.isFinite, activity.movingSeconds.isFinite,
              (0..<1_000_000).contains(activity.distanceMeters),
              (0..<604_800).contains(activity.movingSeconds) else { return nil }
        let trimmed = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? Format.defaultTitle(for: activity.startDate, sport: activity.sport) : trimmed
        user_id = userID
        id = activity.id
        sport = activity.sport.rawValue
        self.title = String(title.prefix(Self.maxTitle))
        start_date = SocialDates.format(activity.startDate)
        distance_m = activity.distanceMeters
        moving_s = activity.movingSeconds
    }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam = "Spam"
    case offensive = "Offensive name or title"
    case impersonation = "Pretending to be someone else"
    case other = "Something else"

    var id: String { rawValue }
}

/// PostgREST writes timestamptz as `2026-09-10T11:00:00.12345+00:00`: a
/// fraction of 0–6 digits (Postgres trims trailing zeroes) that
/// ISO8601DateFormatter's fractional option rejects unless it is exactly
/// three. Second precision is all the feed shows, so the fraction is dropped.
enum SocialDates {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        return f.date(from: s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }

    static func format(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}
