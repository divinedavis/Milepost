import AVFoundation
import Foundation
import Observation

/// Speaks run milestones through the system voice. Music ducks while it
/// talks, podcasts and audiobooks pause, and the audio session is released
/// as soon as the sentence ends so other audio comes back up.
@MainActor
@Observable
final class VoiceAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let defaults: UserDefaults
    /// UI tests run with the voice muted; nothing to assert on and the
    /// simulator's speech stack is slow to start.
    @ObservationIgnored private let isMuted: Bool

    init(defaults: UserDefaults = .standard, isMuted: Bool = false) {
        self.defaults = defaults
        self.isMuted = isMuted
        super.init()
        VoiceCueInterval.migrateSettings(in: defaults)
        synthesizer.delegate = self
    }

    var interval: VoiceCueInterval {
        VoiceCueInterval(rawValue: defaults.string(forKey: VoiceCueInterval.storageKey) ?? "") ?? .half
    }

    var isEnabled: Bool {
        defaults.bool(forKey: VoiceCueInterval.enabledKey)
    }

    func announce(_ milestone: Milestone) {
        guard isEnabled, interval.includes(units: milestone.units) else { return }
        speak(VoiceCuePhrase.text(for: milestone))
    }

    /// What the Settings "Preview" button plays.
    static func sample(unit: DistanceUnit, interval: VoiceCueInterval) -> Milestone {
        Milestone(distanceMeters: unit.meters * interval.units,
                  elapsed: (9 * 60 + 12) * interval.units, unit: unit)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        release()
    }

    func speak(_ text: String) {
        guard !isMuted else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // Speaking still works in the foreground without a session; in the
            // background it will be silent, which is the failure we can live with.
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    private func release() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
