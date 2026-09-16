import Foundation

/// The two Health switches, kept apart on purpose.
///
/// Saving stats to Health and handing Health the route are different promises:
/// the first is a number other fitness apps already have, the second is a map
/// of where the user lives and runs. Milepost's stated position is that routes
/// stay on the phone, so route writing starts off and stays off until the user
/// turns it on, even after they allow Health itself.
enum HealthSettings {
    static let enabledKey = "health.saveWorkouts"
    static let routeKey = "health.includeRoute"
    static let metricsKey = "health.readMetrics"

    static let enabledDefault = false
    static let routeDefault = false
    static let metricsDefault = true
}
