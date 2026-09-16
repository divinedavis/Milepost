import Foundation
import HealthKit
import Observation

/// The iPhone's view of a workout being recorded on the Apple Watch.
///
/// When the watch starts a session it calls `startMirroringToCompanionDevice`,
/// and this handler is how the phone is handed the mirrored session — even if
/// Milepost on the phone was not running, which is the normal case. From there
/// the phone can watch the run and control it.
///
/// The phone never records while a mirrored session is live. Two recorders
/// tracking one run would produce two activities and two workouts in Health.
@MainActor
@Observable
final class MirroredWorkoutMonitor: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    private(set) var isActive = false
    private(set) var state: MirroredWorkoutState?
    private(set) var startDate: Date?

    /// True once the watch has a workout running that this phone is mirroring.
    var isMirroring: Bool { isActive }

    /// Registers for mirrored sessions. Called once at launch; the handler
    /// stays installed for the life of the process.
    func begin() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
    }

    private func adopt(_ session: HKWorkoutSession) {
        session.delegate = self
        self.session = session
        startDate = session.startDate
        isActive = session.state == .running || session.state == .paused || session.state == .prepared
    }

    // MARK: Control

    func pause() { send(.pause) }
    func resume() { send(.resume) }
    func end() { send(.end) }

    private func send(_ command: WorkoutRemoteCommand) {
        guard let session else { return }
        let data = WorkoutRemoteMessage.command(command).data
        Task {
            // A failure here means the watch went out of range. The workout
            // carries on there, which is right — the wrist is the recorder.
            try? await session.sendToRemoteWorkoutSession(data: data)
        }
    }

    private func finish() {
        session = nil
        isActive = false
        state = nil
        startDate = nil
    }
}

extension MirroredWorkoutMonitor: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            switch toState {
            case .running, .paused, .prepared:
                self.isActive = true
            case .ended, .stopped:
                self.finish()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let snapshots = data.compactMap(WorkoutRemoteMessage.decode).compactMap { message -> MirroredWorkoutState? in
            if case let .state(snapshot) = message { return snapshot }
            return nil
        }
        guard let latest = snapshots.last else { return }
        Task { @MainActor in
            self.state = latest
            self.isActive = true
        }
    }
}
