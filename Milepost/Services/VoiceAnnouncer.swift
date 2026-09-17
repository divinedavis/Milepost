import AVFoundation
import Foundation
import Observation

/// Speaks run milestones. The voice is a set of recorded clips
/// (`VoiceCueScript`) stitched together; the system synthesizer is the
/// fallback for anything the library cannot say. Music ducks while it talks,
/// podcasts and audiobooks pause, and the audio session is released as soon
/// as the sentence ends so other audio comes back up.
///
/// Compiled into the watch app too. watchOS routes the session to paired
/// headphones or, from watchOS 11, the speaker; it refuses the ducking
/// options iOS takes, so the session is set up per platform below.
@MainActor
@Observable
final class VoiceAnnouncer: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bundle: Bundle
    /// UI tests run with the voice muted; nothing to assert on and the
    /// simulator's speech stack is slow to start.
    @ObservationIgnored private let isMuted: Bool
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var queue: [URL] = []
    /// What was last played or spoken, for tests and the preview.
    private(set) var lastCue: Cue?

    enum Cue: Equatable {
        case clips([String])
        case synthesized(String)
    }

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main, isMuted: Bool = false) {
        self.defaults = defaults
        self.bundle = bundle
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

    /// Whether the recorded voice shipped with this build.
    var hasRecordedVoice: Bool {
        bundle.url(forResource: VoiceCueScript.clipPrefix + "phrase_time", withExtension: "mp3") != nil
    }

    func announce(_ milestone: Milestone) {
        guard isEnabled, interval.includes(units: milestone.units) else { return }
        play(milestone)
    }

    /// What the Settings "Preview" button plays.
    static func sample(unit: DistanceUnit, interval: VoiceCueInterval) -> Milestone {
        Milestone(distanceMeters: unit.meters * interval.units,
                  elapsed: (9 * 60 + 12) * interval.units, unit: unit)
    }

    /// Says the milestone regardless of the settings: the recorded voice when
    /// every clip it needs is in the bundle, the system voice otherwise.
    func play(_ milestone: Milestone) {
        if let names = VoiceCueScript.clips(for: milestone), let urls = clipURLs(names) {
            lastCue = .clips(names)
            playClips(urls)
        } else {
            speak(VoiceCuePhrase.text(for: milestone))
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue = []
        player?.stop()
        player = nil
        release()
    }

    func speak(_ text: String) {
        lastCue = .synthesized(text)
        guard !isMuted else { return }
        activateSession { [weak self] in
            guard let self else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            self.synthesizer.speak(utterance)
        }
    }

    // MARK: Clips

    private func clipURLs(_ names: [String]) -> [URL]? {
        var urls: [URL] = []
        for name in names {
            guard let url = bundle.url(forResource: VoiceCueScript.clipPrefix + name, withExtension: "mp3") else { return nil }
            urls.append(url)
        }
        return urls
    }

    private func playClips(_ urls: [URL]) {
        guard !isMuted else { return }
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        activateSession { [weak self] in
            guard let self else { return }
            self.queue = urls
            self.playNext()
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            player = nil
            release()
            return
        }
        let url = queue.removeFirst()
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            next.prepareToPlay()
            player = next
            next.play()
        } catch {
            // A clip that will not decode should not silence the rest.
            playNext()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNext() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.playNext() }
    }

    // MARK: Session

    private func activateSession(then run: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()
        #if os(watchOS)
        // watchOS rejects duckOthers / mixWithOthers, and playback goes
        // through activate(options:), which is what routes to headphones.
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .default, options: [])
        session.activate(options: []) { _, _ in
            Task { @MainActor in run() }
        }
        #else
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // Speaking still works in the foreground without a session; in the
            // background it will be silent, which is the failure we can live with.
        }
        run()
        #endif
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    private func release() {
        guard !synthesizer.isSpeaking, player == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
