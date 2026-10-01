import Foundation
import Observation
import SwiftData
import WatchConnectivity

/// Receives activities recorded on the Apple Watch.
///
/// The watch queues them with `transferUserInfo`, so they arrive whenever the
/// phone next has the watch in range — including while Milepost is in the
/// background, which is the normal case: the run ends on the wrist and the
/// phone is in a pocket or on a table at home.
@MainActor
@Observable
final class PhoneWatchSync: NSObject {
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var lastReceived: Date?
    private(set) var lastError: String?

    /// Set by the app once the model container exists. Returns true when the
    /// activity was stored, false when it was already there.
    var onReceive: (@MainActor (WatchActivityPayload) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Mirrors the phone's Health settings onto the watch.
    ///
    /// `updateApplicationContext` replaces whatever was sent last and is
    /// delivered whenever the watch next comes into range, which is exactly the
    /// shape of a setting: there is no history worth queueing, only the current
    /// value. It matters that this reaches the watch at all — without it the
    /// watch would have to pick its own default for whether a route goes into
    /// Health, and the honest default and the useful one are not the same.
    ///
    /// The voice settings ride along: a runner who turned announcements off on
    /// the phone must not get them back on the wrist. Nil reads the current
    /// values off UserDefaults, which is where every toggle has already
    /// written by the time its onChange fires.
    func pushSettings(includeRouteInHealth: Bool? = nil) {
        guard let session, session.activationState == .activated else { return }
        let defaults = UserDefaults.standard
        let context: [String: Any] = [
            HealthSettings.routeKey: includeRouteInHealth ?? defaults.bool(forKey: HealthSettings.routeKey),
            VoiceCueInterval.enabledKey: defaults.bool(forKey: VoiceCueInterval.enabledKey),
            VoiceCueInterval.storageKey: defaults.string(forKey: VoiceCueInterval.storageKey) ?? VoiceCueInterval.half.rawValue,
            AutoPauseSettings.enabledKey: AutoPauseSettings.isEnabled(defaults),
        ]
        do {
            try session.updateApplicationContext(context)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshPairing(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let message = error?.localizedDescription
        let includeRoute = UserDefaults.standard.bool(forKey: HealthSettings.routeKey)
        Task { @MainActor in
            self.lastError = message
            self.refreshPairing(session)
            // The watch may have been installed or reset since the last launch.
            self.pushSettings(includeRouteInHealth: includeRoute)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The paired watch changed. The session has to be reactivated or nothing
    /// from the new watch ever arrives.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshPairing(session) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchActivityPayload.userInfoKey] as? Data else { return }
        Task { @MainActor in
            do {
                let payload = try JSONDecoder().decode(WatchActivityPayload.self, from: data)
                guard payload.schema <= WatchActivityPayload.currentSchema else {
                    // A newer watch build sending a shape this app cannot read.
                    // Dropping it quietly is better than storing half of it.
                    self.lastError = "This activity came from a newer version of Milepost on your Apple Watch. Update the app on your iPhone to see it."
                    return
                }
                self.onReceive?(payload)
                self.lastReceived = Date()
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }
}

/// Turning a payload from the watch into a stored activity.
@MainActor
enum WatchActivityImporter {
    /// Inserts the activity if it is not already there. Returns the activity,
    /// new or existing, or nil when it could not be stored.
    @discardableResult
    static func store(_ payload: WatchActivityPayload, in context: ModelContext) -> Activity? {
        let id = payload.id
        var descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // The watch retries a transfer it never saw acknowledged, so the same
        // run can arrive twice.
        if let existing = try? context.fetch(descriptor).first { return existing }

        let activity = Activity(id: payload.id, title: payload.title,
                                startDate: payload.startDate,
                                endDate: payload.endDate,
                                movingSeconds: payload.movingSeconds,
                                distanceMeters: payload.distanceMeters,
                                splitMeters: payload.splitMeters,
                                route: payload.route,
                                splits: payload.splits,
                                sport: payload.sport,
                                pauses: payload.pauses)
        // The watch already wrote the workout to Health. Recording its id here
        // is what stops the phone writing a second copy of the same run.
        activity.healthWorkoutID = payload.healthWorkoutID
        // Heart rate and calories are deliberately not stored on the activity.
        // The watch wrote them to Health, and the detail screen reads them back
        // from there by date range — so they are shown without Milepost holding
        // a second copy of health data it has no need to own, and without any
        // chance of one reaching the friends backend.
        context.insert(activity)
        try? context.save()
        return activity
    }
}
