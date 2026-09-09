import SwiftData
import SwiftUI

struct YouScreen: View {
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(VoiceCueInterval.storageKey) private var voiceRaw = VoiceCueInterval.off.rawValue
    @Environment(VoiceAnnouncer.self) private var announcer

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var voice: VoiceCueInterval { VoiceCueInterval(rawValue: voiceRaw) ?? .off }

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

                    Picker("Voice cues", selection: $voiceRaw) {
                        ForEach(VoiceCueInterval.allCases) { v in
                            Text(v.title(unit: unit)).tag(v.rawValue)
                        }
                    }
                    .accessibilityIdentifier("you.voiceCues")

                    Button("Preview voice") {
                        announcer.speak(VoiceCuePhrase.text(for: VoiceAnnouncer.sample))
                    }
                    .disabled(voice == .off)
                    .accessibilityIdentifier("you.voicePreview")
                } header: {
                    Text("Settings")
                } footer: {
                    Text(voiceFooter)
                }

                Section("About") {
                    LabeledContent("Version", value: Self.versionText)
                    Text("Runs are stored on this phone only. Nothing is uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
        let noun = unit.splitNoun.lowercased()
        switch voice {
        case .off: return "Voice cues read out your time and average pace, over your music, even with the screen off."
        case .full: return "Spoken at every \(noun), over your music, even with the screen off."
        case .half: return "Spoken at every half \(noun), over your music, even with the screen off."
        }
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
