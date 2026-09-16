import SwiftData
import SwiftUI

struct YouScreen: View {
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(VoiceCueInterval.storageKey) private var voiceRaw = VoiceCueInterval.half.rawValue
    @AppStorage(VoiceCueInterval.enabledKey) private var voiceEnabled = true
    @Environment(VoiceAnnouncer.self) private var announcer
    @Environment(RunRecorder.self) private var recorder

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var voice: VoiceCueInterval { VoiceCueInterval(rawValue: voiceRaw) ?? .half }
    private var voiceUnit: DistanceUnit { recorder.isActive ? recorder.unit : unit }

    var body: some View {
        NavigationStack {
            List {
                let week = ActivityStats.thisWeek(activities)
                let all = ActivityStats.totals(activities)

                Section("This week") { totals(week) }
                Section("All time") { totals(all) }

                Section {
                    Picker("Units", selection: $unitRaw) {
                        ForEach(DistanceUnit.allCases) { u in
                            Text(u.title).tag(u.rawValue)
                        }
                    }
                    .accessibilityIdentifier("you.units")

                    Toggle("Voice announcements", isOn: $voiceEnabled)
                        .accessibilityIdentifier("you.voiceEnabled")
                        .onChange(of: voiceEnabled) { _, enabled in
                            if !enabled { announcer.stop() }
                        }

                    Picker("Announce distance", selection: $voiceRaw) {
                        ForEach(VoiceCueInterval.selectable) { v in
                            Text(v.title(unit: voiceUnit)).tag(v.rawValue)
                        }
                    }
                    .disabled(!voiceEnabled)
                    .accessibilityIdentifier("you.voiceCues")

                    Button("Preview voice") {
                        announcer.speak(VoiceCuePhrase.text(for: VoiceAnnouncer.sample(unit: voiceUnit, interval: voice)))
                    }
                    .disabled(!voiceEnabled)
                    .accessibilityIdentifier("you.voicePreview")
                } header: {
                    Text("Settings")
                } footer: {
                    Text(voiceFooter)
                }

                HealthSection()

                AccountSection()

                Section("About") {
                    LabeledContent("Version", value: Self.versionText)
                    Text("Routes are stored on this phone only. With friends on, only each activity's stats are shared, and a route reaches Apple Health only if you switch it on above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationDestination(for: FriendsRoute.self) { _ in FriendsScreen() }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("Wordmark").accessibilityLabel("Milepost")
                }
            }
        }
    }

    private var voiceFooter: String {
        let example = VoiceCuePhrase.distance(voice.units, unit: voiceUnit)
        return "\(example) Hear your completed distance, time and average pace or speed over your music, even with the screen off. Changes apply at the next matching distance."
    }

    private func totals(_ t: ActivityTotals) -> some View {
        Group {
            LabeledContent("Activities", value: "\(t.count)")
            LabeledContent("Distance", value: "\(Format.distance(t.distanceMeters, unit: unit)) \(unit.abbreviation)")
            LabeledContent("Time", value: Format.duration(t.seconds))
            LabeledContent("Avg. pace", value: "\(Format.pace(t.averagePace(unit: unit))) \(unit.paceSuffix)")
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
