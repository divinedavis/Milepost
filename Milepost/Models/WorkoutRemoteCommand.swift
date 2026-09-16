import Foundation

/// The two-way channel between a workout running on the Apple Watch and the
/// mirrored copy of it on the iPhone.
///
/// These travel over `HKWorkoutSession.sendToRemoteWorkoutSession(data:)`,
/// which is a raw byte channel between the mirrored sessions. It is not
/// WatchConnectivity: it works while either app is in the background, which is
/// the only reason the phone can show a live run at all — during a workout the
/// phone app is not in the foreground and the watch is.
///
/// Everything is JSON with a named case, so a newer build on one device meeting
/// an older one on the other decodes to nothing and is ignored, rather than
/// being misread as a different message.
enum WorkoutRemoteMessage: Codable, Equatable {
    /// iPhone → Apple Watch. The watch owns the recording; the phone asks.
    case command(WorkoutRemoteCommand)
    /// Apple Watch → iPhone, a few times a minute while recording.
    case state(MirroredWorkoutState)

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    static func decode(_ data: Data) -> WorkoutRemoteMessage? {
        try? JSONDecoder().decode(WorkoutRemoteMessage.self, from: data)
    }
}

enum WorkoutRemoteCommand: String, Codable, Equatable {
    case pause
    case resume
    case end
}

/// A snapshot of a run in progress on the wrist, as the phone should draw it.
///
/// Sent already-computed rather than as raw inputs: the watch is the only
/// device with the recorder that has seen every GPS fix, so it is the only one
/// that can say what the pace is. The phone renders what it is told.
struct MirroredWorkoutState: Codable, Equatable {
    var sportRaw: String
    var unitRaw: String
    var distanceMeters: Double
    var elapsed: TimeInterval
    /// Nil when the pace is outside the plausible range for the sport, which is
    /// what the phone's own engine would have decided too.
    var paceSecondsPerUnit: Double?
    var heartRate: Double?
    var activeKilocalories: Double?
    var isPaused: Bool
    /// When the stopwatch would have started to read `elapsed`. Lets the phone
    /// tick a `Text(_:style:.timer)` between updates instead of showing a
    /// number that jumps every two seconds.
    var elapsedAnchor: Date?

    var sport: Sport { Sport(rawValue: sportRaw) ?? .run }
    var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
}
