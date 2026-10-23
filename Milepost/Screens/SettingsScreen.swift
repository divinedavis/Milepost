import SwiftUI

/// Profile > Settings: units, auto-pause and voice. These were a section on
/// the You tab until Profile took its card layout (2026-10-22).
struct SettingsScreen: View {
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(VoiceCueInterval.storageKey) private var voiceRaw = VoiceCueInterval.half.rawValue
    @AppStorage(VoiceCueInterval.enabledKey) private var voiceEnabled = true
    @AppStorage(AutoPauseSettings.enabledKey) private var autoPause = AutoPauseSettings.enabledDefault
    @AppStorage(HolidayIcon.settingKey) private var holidayIcons = HolidayIcon.enabledDefault
    @Environment(VoiceAnnouncer.self) private var announcer
    @Environment(RunRecorder.self) private var recorder
    @Environment(PhoneWatchSync.self) private var watchSync

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var voice: VoiceCueInterval { VoiceCueInterval(rawValue: voiceRaw) ?? .half }
    private var voiceUnit: DistanceUnit { recorder.isActive ? recorder.unit : unit }

    var body: some View {
        List {
            Section {
                Picker("Units", selection: $unitRaw) {
                    ForEach(DistanceUnit.allCases) { u in
                        Text(u.title).tag(u.rawValue)
                    }
                }
                .accessibilityIdentifier("you.units")

                Toggle(isOn: $autoPause) {
                    Text("Auto-pause")
                    Text("Stops the clock when you stand still, or slow to a walk on a run, and restarts it when you get going.")
                }
                .accessibilityIdentifier("you.autoPause")
                .onChange(of: autoPause) { _, _ in watchSync.pushSettings() }
            }

            Section {
                Toggle(isOn: $holidayIcons) {
                    Text("Holiday app icons")
                    Text("Your Home Screen icon wears the colors of holidays like Thanksgiving and Juneteenth, then switches back.")
                }
                .accessibilityIdentifier("you.holidayIcons")
                .onChange(of: holidayIcons) { _, _ in HolidayIcon.apply() }
            }

            Section {
                Toggle("Voice announcements", isOn: $voiceEnabled)
                    .accessibilityIdentifier("you.voiceEnabled")
                    .onChange(of: voiceEnabled) { _, enabled in
                        if !enabled { announcer.stop() }
                        watchSync.pushSettings()
                    }

                Picker("Announce distance", selection: $voiceRaw) {
                    ForEach(VoiceCueInterval.selectable) { v in
                        Text(v.title(unit: voiceUnit)).tag(v.rawValue)
                    }
                }
                .disabled(!voiceEnabled)
                .accessibilityIdentifier("you.voiceCues")
                .onChange(of: voiceRaw) { _, _ in watchSync.pushSettings() }

                Button("Preview voice") {
                    announcer.play(VoiceAnnouncer.sample(unit: voiceUnit, interval: voice))
                }
                .disabled(!voiceEnabled)
                .accessibilityIdentifier("you.voicePreview")
            } footer: {
                Text(voiceFooter)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var voiceFooter: String {
        let example = VoiceCuePhrase.distance(voice.units, unit: voiceUnit)
        return "\(example) Hear your completed distance, time and average pace or speed over your music, even with the screen off. Changes apply at the next matching distance."
    }
}
