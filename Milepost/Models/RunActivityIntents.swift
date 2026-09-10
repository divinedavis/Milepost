import AppIntents
import Foundation

/// The bridge from a button on the Live Activity back to the recorder.
///
/// The intent type is compiled into the widget extension as well as the app,
/// so nothing in this file may touch the engine directly. The app registers a
/// closure at launch and the intent calls it. That is safe because a
/// `LiveActivityIntent` always runs in the **app's** process — the system
/// wakes the app in the background to run it — never in the widget's.
@MainActor
enum RunActivityActions {
    /// Pause a recording activity, resume a paused one. Set by MilepostApp;
    /// nil in the widget process, where the intent never runs.
    static var toggleRecording: (() -> Void)?
}

/// The Pause / Resume button on the Dynamic Island and the lock screen.
struct ToggleRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume"
    static var description = IntentDescription("Pauses or resumes the activity Milepost is recording.")
    /// Pausing from the lock screen should not throw the app on screen.
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { RunActivityActions.toggleRecording?() }
        return .result()
    }
}
