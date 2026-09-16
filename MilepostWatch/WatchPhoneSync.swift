import Foundation
import Observation
import WatchConnectivity

/// Sends a finished activity from the watch to the phone.
///
/// `transferUserInfo` rather than `sendMessage`: it is queued and delivered
/// whenever the phone next becomes reachable, so a run finished out of
/// Bluetooth range still lands. The queue survives the watch app being killed,
/// which matters because the natural thing to do after a run is lower the wrist
/// and forget about it.
@MainActor
@Observable
final class WatchPhoneSync: NSObject {
    private(set) var pendingCount = 0
    private(set) var lastError: String?
    /// Whether a route may be written to Health, as set on the iPhone. Starts
    /// off, like the phone's own switch, so a watch that has never heard from
    /// its phone errs toward not writing one.
    private(set) var includeRouteInHealth = false

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        // Whatever the phone last sent is already on disk here; the delegate
        // callback only fires when it changes.
        apply(session.receivedApplicationContext)
    }

    private func apply(_ context: [String: Any]) {
        guard let includeRoute = context[HealthSettings.routeKey] as? Bool else { return }
        includeRouteInHealth = includeRoute
    }

    /// Queues the activity for the phone. Returns false when this watch has no
    /// paired phone at all, in which case the workout still lives in Health.
    @discardableResult
    func send(_ payload: WatchActivityPayload) -> Bool {
        guard let session else { return false }
        do {
            let data = try JSONEncoder().encode(payload)
            session.transferUserInfo([WatchActivityPayload.userInfoKey: data])
            pendingCount = session.outstandingUserInfoTransfers.count
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

extension WatchPhoneSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let message = error?.localizedDescription
        let outstanding = session.outstandingUserInfoTransfers.count
        Task { @MainActor in
            self.lastError = message
            self.pendingCount = outstanding
        }
    }

    /// The iPhone's Health settings changed.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let message = error?.localizedDescription
        let outstanding = session.outstandingUserInfoTransfers.count
        Task { @MainActor in
            if let message { self.lastError = message }
            self.pendingCount = outstanding
        }
    }
}
