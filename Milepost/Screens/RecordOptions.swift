import SwiftUI

/// What the Record panel shows when it is pulled up (owner, 2026-10-22,
/// from a Strava recording): the run settings people change before a run,
/// without leaving the map. Only things Milepost actually does; Strava's
/// live location, route alerts and sensors have no Milepost equivalent.
struct RecordOptions: View {
    @Environment(PhoneWatchSync.self) private var watchSync
    @Environment(VoiceAnnouncer.self) private var announcer
    @AppStorage(AutoPauseSettings.enabledKey) private var autoPause = AutoPauseSettings.enabledDefault
    @AppStorage(VoiceCueInterval.enabledKey) private var voiceEnabled = true
    @AppStorage(VoiceCueInterval.storageKey) private var voiceRaw = VoiceCueInterval.half.rawValue
    @AppStorage(HeatmapWindow.storageKey) private var heatRaw = HeatmapWindow.default.rawValue
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(HealthSettings.enabledKey) private var healthEnabled = HealthSettings.enabledDefault

    @State private var sheet: Destination?

    enum Destination: String, Identifiable {
        case health, settings
        var id: String { rawValue }
    }

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var voice: VoiceCueInterval { VoiceCueInterval(rawValue: voiceRaw) ?? .half }
    private var heatWindow: HeatmapWindow { HeatmapWindow(rawValue: heatRaw) ?? .default }

    var body: some View {
        VStack(spacing: 0) {
            toggleRow("Auto-pause", subtitle: "Stops the clock when you stop", symbol: "pause.circle",
                      isOn: $autoPause, id: "record.option.autoPause")
                .onChange(of: autoPause) { _, _ in watchSync.pushSettings() }
            divider
            toggleRow("Voice announcements", subtitle: voiceEnabled ? voice.title(unit: unit) : "Off",
                      symbol: "speaker.wave.2", isOn: $voiceEnabled, id: "record.option.voice")
                .onChange(of: voiceEnabled) { _, on in
                    if !on { announcer.stop() }
                    watchSync.pushSettings()
                }
            divider
            menuRow("Past routes on map", symbol: "map", value: heatWindow == .off ? "Off" : heatWindow.title,
                    id: "record.option.pastRoutes") {
                Picker("Past routes on map", selection: $heatRaw) {
                    ForEach(HeatmapWindow.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            divider
            menuRow("Units", symbol: "ruler", value: unit.title, id: "record.option.units") {
                Picker("Units", selection: $unitRaw) {
                    ForEach(DistanceUnit.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            divider
            linkRow("Apple Health", subtitle: healthEnabled ? "Saving workouts" : "Off",
                    symbol: "heart", id: "record.option.health") { sheet = .health }
            divider
            linkRow("Settings", subtitle: "Voice cues, auto-pause, units",
                    symbol: "gearshape", id: "record.option.settings") { sheet = .settings }
        }
        .sheet(item: $sheet) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .health: List { HealthSection() }.navigationTitle("Apple Health")
                    case .settings: SettingsScreen()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { sheet = nil }
                            .accessibilityIdentifier("record.option.done")
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 52)
    }

    private func label(_ title: String, subtitle: String?, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
        }
    }

    private func toggleRow(_ title: String, subtitle: String?, symbol: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) { label(title, subtitle: subtitle, symbol: symbol) }
            .tint(Theme.accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .accessibilityIdentifier(id)
    }

    private func menuRow<Content: View>(_ title: String, symbol: String, value: String, id: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack {
                label(title, subtitle: nil, symbol: symbol)
                Text(value).font(.subheadline).foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }

    private func linkRow(_ title: String, subtitle: String, symbol: String, id: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                label(title, subtitle: subtitle, symbol: symbol)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
