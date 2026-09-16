import Foundation

/// A finished activity on its way from the Apple Watch to the phone.
///
/// The watch is the recorder in this direction, so the payload carries
/// everything the phone needs to build the same `Activity` it would have built
/// itself — including the route, which stays inside the pair of devices and is
/// never uploaded anywhere.
///
/// `schema` exists because the two apps update independently: a watch running a
/// newer build must not hand the phone a shape it cannot read.
struct WatchActivityPayload: Codable, Equatable {
    static let currentSchema = 1
    /// The key the payload travels under in a WatchConnectivity message.
    static let userInfoKey = "milepost.activity"

    var schema: Int = currentSchema
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    var splitMeters: Double
    var sportRaw: String
    var route: [RoutePoint]
    var splits: [Split]
    var pauses: [PauseInterval]
    /// Heart rate and energy the watch measured. The phone cannot re-derive
    /// these, and it should not re-estimate calories over the top of a figure
    /// that came from a wrist.
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeKilocalories: Double?
    /// The watch writes the workout to Health itself, so the phone must not
    /// write a second one. Non-nil means Health already has it.
    var healthWorkoutID: String?

    var sport: Sport { Sport(rawValue: sportRaw) ?? .run }

    var summary: RunSummary {
        RunSummary(startDate: startDate,
                   endDate: endDate,
                   movingSeconds: movingSeconds,
                   distanceMeters: distanceMeters,
                   splitMeters: splitMeters,
                   route: route,
                   splits: splits,
                   sport: sport,
                   pauses: pauses)
    }

    init(id: UUID = UUID(),
         title: String,
         summary: RunSummary,
         averageHeartRate: Double? = nil,
         maxHeartRate: Double? = nil,
         activeKilocalories: Double? = nil,
         healthWorkoutID: String? = nil) {
        self.id = id
        self.title = title
        startDate = summary.startDate
        endDate = summary.endDate
        movingSeconds = summary.movingSeconds
        distanceMeters = summary.distanceMeters
        splitMeters = summary.splitMeters
        sportRaw = summary.sport.rawValue
        route = summary.route
        splits = summary.splits
        pauses = summary.pauses
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeKilocalories = activeKilocalories
        self.healthWorkoutID = healthWorkoutID
    }
}
