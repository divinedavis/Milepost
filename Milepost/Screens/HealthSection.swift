import SwiftUI

/// The Apple Health switches on the You tab.
///
/// Two toggles, not one, because they are two different promises: the first
/// puts the workout's numbers where every other fitness app can read them, the
/// second hands over a map of where the user actually goes. The route switch is
/// off by default and only appears once saving is on.
struct HealthSection: View {
    @Environment(HealthKitService.self) private var health
    @Environment(PhoneWatchSync.self) private var watchSync
    @AppStorage(HealthSettings.enabledKey) private var enabled = HealthSettings.enabledDefault
    @AppStorage(HealthSettings.routeKey) private var includeRoute = HealthSettings.routeDefault
    @AppStorage(HealthSettings.metricsKey) private var readMetrics = HealthSettings.metricsDefault

    @State private var isAsking = false

    var body: some View {
        if HealthKitService.isSupported {
            Section {
                Toggle("Save to Apple Health", isOn: $enabled)
                    .accessibilityIdentifier("you.healthEnabled")
                    .disabled(isAsking)
                    .onChange(of: enabled) { _, on in
                        guard on else { return }
                        askForPermission()
                    }

                if enabled {
                    Toggle("Include route", isOn: $includeRoute)
                        .accessibilityIdentifier("you.healthRoute")
                        // The watch writes its own workouts, so it has to be
                        // told, or the switch would only govern half the app.
                        .onChange(of: includeRoute) { _, include in
                            watchSync.pushSettings(includeRouteInHealth: include)
                        }

                    Toggle("Show heart rate and Watch data", isOn: $readMetrics)
                        .accessibilityIdentifier("you.healthMetrics")
                }

                NavigationLink {
                    OuraGuideView()
                } label: {
                    Label("Use with Oura Ring", systemImage: "circle.circle")
                }
                .accessibilityIdentifier("you.oura")
            } header: {
                Text("Apple Health")
            } footer: {
                Text(footer)
                    .accessibilityIdentifier("you.healthFooter")
            }
        }
    }

    private var footer: String {
        if let error = health.lastError, enabled {
            return error
        }
        if enabled && !health.canWriteWorkouts && health.hasBeenAsked {
            return "Milepost cannot add workouts yet. Turn Milepost on in Health > Sharing > Apps > Milepost."
        }
        if !enabled {
            return "Add every activity to Health as a workout, so its distance, time and calories count toward your rings and any other fitness app can read them. Turning this on is also what lets Milepost show the heart rate your Apple Watch or Oura Ring recorded."
        }
        var lines = ["Each saved activity becomes a workout in Health, with its splits as laps and an estimated calorie burn."]
        lines.append(includeRoute
            ? "Your route is written to Health too. It stays on this device — Health does not send it to Milepost or to your friends."
            : "Your route is not written. Only the numbers go to Health.")
        if readMetrics {
            lines.append("Heart rate and other metrics recorded by an Apple Watch or Oura Ring are shown on each activity.")
        }
        return lines.joined(separator: " ")
    }

    private func askForPermission() {
        isAsking = true
        Task {
            let granted = await health.requestAuthorization()
            if granted { await health.refreshBodyMass() }
            isAsking = false
            // The switch is deliberately left on when permission was refused.
            // iOS only ever shows its sheet once, so snapping the switch back
            // would leave someone who denied it by accident with a control that
            // does nothing and says nothing; on, the footer can tell them where
            // in Settings to fix it. Nothing is written either way — every
            // write checks `canWriteWorkouts` first.
        }
    }
}
