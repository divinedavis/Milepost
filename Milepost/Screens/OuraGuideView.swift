import SwiftUI

/// How Milepost and an Oura Ring work together, reached from the Health
/// section on the You tab.
///
/// There is no direct link to the ring: Oura shares only through its own app,
/// which trades data with Apple Health. So "Oura support" is Health support
/// plus two switches in the Oura app, and this screen is where those are
/// explained. Oura imports a workout only on the day it happened and only once
/// its app is opened, which is why step 3 exists.
struct OuraGuideView: View {
    @Environment(HealthKitService.self) private var health
    @AppStorage(HealthSettings.enabledKey) private var healthEnabled = HealthSettings.enabledDefault
    @AppStorage(HealthSettings.metricsKey) private var readMetrics = HealthSettings.metricsDefault

    var body: some View {
        List {
            Section {
                Text("Your runs, walks and rides count toward Oura's Activity score, and the heart rate your ring measured shows on each activity in Milepost. Everything passes through Apple Health.")
            }

            Section("In Milepost") {
                step(1, "Turn on Save to Apple Health", done: healthEnabled && health.canWriteWorkouts,
                     detail: healthEnabled
                        ? "On. If Health asked and you said no, allow Milepost in Health > Sharing > Apps."
                        : "Go back and turn on Save to Apple Health, then allow Milepost when Health asks.")
                    .accessibilityIdentifier("oura.stepHealth")
                step(2, "Keep Show heart rate on", done: healthEnabled && readMetrics,
                     detail: "This is what lets Milepost read the heart rate Oura writes to Health.")
            }

            Section("In the Oura app") {
                step(3, "Connect Apple Health", done: nil,
                     detail: "Open Settings (top left of the home tab) > Apple Health. Let Oura read Workouts and write Heart Rate.")
                step(4, "Open Oura after each activity", done: nil,
                     detail: "Oura only syncs with Health while its app is open, and only imports workouts from the same day.")
            }

            Section {
                Text("Oura may also detect a run of 10 minutes or more on its own. If an activity shows up twice in Oura, delete one of them there — Milepost cannot change Oura's list.")
                Text("The ring sends nothing live: heart rate appears on an activity once Oura has synced, not during it.")
            } header: {
                Text("Good to know")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Oura Ring")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, done: Bool?, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done == true ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title3)
                .foregroundStyle(done == true ? Color.green : Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
