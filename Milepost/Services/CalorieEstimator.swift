import Foundation

/// Active energy for a GPS-only activity.
///
/// A phone has no heart rate, so calories have to be modelled from speed and
/// body mass. This uses the ACSM metabolic equations for walking and running,
/// which are defined in terms of horizontal speed, and the Compendium of
/// Physical Activities MET bands for cycling, which is dominated by air drag
/// and has no comparable closed form.
///
/// The result is an estimate and is labelled as one everywhere it is shown. A
/// heart-rate-derived figure from a Watch is always better, so
/// `HealthKitService` prefers one when Health already has it.
enum CalorieEstimator {
    /// What Health uses when the user has never entered a weight. Health's own
    /// default for an adult; the estimate scales linearly with it, so a wrong
    /// weight is a proportional error, not a wild one.
    static let defaultBodyMassKilograms: Double = 70

    /// Resting oxygen uptake, ml/kg/min. One MET.
    private static let restingVO2: Double = 3.5

    /// Metabolic equivalents for an activity at this average speed.
    ///
    /// - Parameter metersPerSecond: average moving speed, not elapsed speed.
    static func metabolicEquivalent(sport: Sport, metersPerSecond: Double) -> Double {
        let metersPerMinute = max(0, metersPerSecond) * 60
        switch sport {
        case .walk:
            // ACSM walking: VO2 = 0.1 * speed + 3.5 (ml/kg/min), level ground.
            return (0.1 * metersPerMinute + restingVO2) / restingVO2
        case .run, .strollerRun:
            // ACSM running: VO2 = 0.2 * speed + 3.5. Pushing a stroller costs
            // more than running free, but by how much is not something the
            // published equations answer, so a stroller run is modelled as a
            // run rather than with a number made up here.
            return (0.2 * metersPerMinute + restingVO2) / restingVO2
        case .bike:
            // Compendium of Physical Activities, outdoor cycling by speed.
            // Drag grows with the cube of speed, so the bands step steeply.
            let kmh = metersPerSecond * 3.6
            switch kmh {
            case ..<16: return 4.0
            case ..<19: return 6.8
            case ..<22: return 8.0
            case ..<25: return 10.0
            case ..<30: return 12.0
            default: return 15.8
            }
        }
    }

    /// Active kilocalories burned, or nil when there is not enough to model.
    ///
    /// Active energy is energy *above* resting, which is what Health's Move
    /// ring counts, so one MET is subtracted before converting.
    static func activeKilocalories(sport: Sport,
                                   distanceMeters: Double,
                                   movingSeconds: TimeInterval,
                                   bodyMassKilograms: Double = defaultBodyMassKilograms) -> Double? {
        guard distanceMeters > 0, movingSeconds > 0, bodyMassKilograms > 0 else { return nil }
        let speed = distanceMeters / movingSeconds
        // Outside the plausible range for the sport the speed is GPS noise, not
        // athletics, and the number it would produce is worse than none.
        guard let secondsPerUnit = Pace.secondsPerUnit(distanceMeters: distanceMeters,
                                                       seconds: movingSeconds,
                                                       unit: .miles,
                                                       sport: sport),
              secondsPerUnit > 0 else { return nil }
        let mets = metabolicEquivalent(sport: sport, metersPerSecond: speed)
        let activeMETs = max(0, mets - 1)
        let minutes = movingSeconds / 60
        // kcal/min = METs * 3.5 * kg / 200
        return activeMETs * restingVO2 * bodyMassKilograms / 200 * minutes
    }
}
