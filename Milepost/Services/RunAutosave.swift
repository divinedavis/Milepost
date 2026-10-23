import Foundation
import Observation
import SwiftData
import SwiftUI

/// Keeps the run in progress on disk, so a phone that dies (battery, a crash,
/// iOS killing the app) mid-run does not lose it. Every `interval` seconds
/// while recording, and whenever the app leaves the screen, the recorder's
/// `RunCheckpoint` is written to Application Support. The next launch turns a
/// leftover checkpoint into a saved activity (`RunRecovery`).
///
/// Until 2026-10-22 a run lived only in memory: a walker in York, PA lost the
/// whole thing when the app died halfway round.
@MainActor
final class RunAutosave {
    /// At most this much of a run is lost. A one-hour route is a few hundred
    /// KB of JSON, so writing it this often costs nothing worth measuring.
    static let interval: TimeInterval = 10

    let fileURL: URL
    private weak var recorder: RunRecorder?
    private var timer: Timer?
    /// Set once this process has written a checkpoint. Only then may an idle
    /// recorder delete the file: at launch the file on disk is the previous
    /// run's, waiting for `RunRecovery`.
    private var wroteThisSession = false
    /// Writes and deletes go through one serial queue, so a slow write can
    /// never land after the delete that followed it and bring a run back.
    private let queue = DispatchQueue(label: "com.divinedavis.milepost.autosave")

    init(recorder: RunRecorder, fileURL: URL = RunAutosave.defaultURL) {
        self.recorder = recorder
        self.fileURL = fileURL
    }

    nonisolated static var defaultURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("run-in-progress.json")
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Writes now (recording) or clears a finished run's file (idle).
    func tick() {
        guard let recorder else { return }
        if let checkpoint = recorder.checkpoint() {
            write(checkpoint)
        } else if wroteThisSession {
            clear()
        }
    }

    func write(_ checkpoint: RunCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        wroteThisSession = true
        let url = fileURL
        queue.async {
            // Until-first-unlock, not complete: the screen is usually locked
            // mid-run and a complete-protection file cannot be written then.
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func clear() {
        wroteThisSession = false
        let url = fileURL
        queue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// The checkpoint a previous process left behind, if any. Read
    /// synchronously at launch, before anything could write a new one.
    func pending() -> RunCheckpoint? {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let checkpoint = try? JSONDecoder().decode(RunCheckpoint.self, from: data),
                  checkpoint.version == RunCheckpoint.currentVersion else { return nil }
            return checkpoint
        }
    }

    /// Blocks until queued writes and deletes have landed. Tests only.
    func flush() { queue.sync {} }
}

/// What the Record tab tells the user after a run was rescued at launch.
@MainActor
@Observable
final class RunRecovery {
    struct Recovered: Equatable {
        var activityID: UUID
        var sport: Sport
        var distanceMeters: Double
    }

    var recovered: Recovered?

    /// Saves a leftover checkpoint as an activity and clears it. Returns the
    /// activity so the caller can share it / write it to Health the way a
    /// normal save does. A checkpoint that never moved is dropped, as Finish
    /// would have dropped it.
    @discardableResult
    func recover(from autosave: RunAutosave, into context: ModelContext) -> Activity? {
        defer { autosave.clear() }
        guard let checkpoint = autosave.pending(), let summary = checkpoint.summary else { return nil }
        let activity = Activity(summary: summary,
                                title: Format.defaultTitle(for: summary.startDate, sport: summary.sport))
        context.insert(activity)
        try? context.save()
        recovered = Recovered(activityID: activity.id, sport: summary.sport,
                              distanceMeters: summary.distanceMeters)
        return activity
    }
}

extension EnvironmentValues {
    /// So Finish / Discard can clear the file the moment a run ends, instead
    /// of on the next tick.
    @Entry var runAutosave: RunAutosave? = nil
}
