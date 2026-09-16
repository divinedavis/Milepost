import SwiftUI

/// What a wrist measured while the phone was in a pocket.
///
/// Milepost records none of this itself. It is read back out of Health for the
/// window the activity covers, so a run tracked on the phone still shows the
/// heart rate an Apple Watch was recording at the same time, whichever app
/// wrote the workout.
struct HealthMetricsSection: View {
    let activity: Activity
    @Environment(HealthKitService.self) private var health
    @AppStorage(HealthSettings.metricsKey) private var readMetrics = HealthSettings.metricsDefault
    @State private var metrics: HealthMetrics?

    var body: some View {
        Group {
            if let metrics, !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("From Apple Health", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.orange)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        if let bpm = metrics.averageHeartRate {
                            tile("Avg. heart rate", "\(Int(bpm.rounded())) bpm")
                        }
                        if let bpm = metrics.maxHeartRate {
                            tile("Max heart rate", "\(Int(bpm.rounded())) bpm")
                        }
                        if let kcal = metrics.activeKilocalories {
                            tile("Active calories", "\(Int(kcal.rounded())) kcal")
                        }
                        if let steps = metrics.stepCount {
                            tile("Steps", "\(Int(steps.rounded()))")
                        }
                        if let watts = metrics.averageRunningPower {
                            tile("Avg. running power", "\(Int(watts.rounded())) W")
                        }
                        if let stride = metrics.averageStrideLengthMeters {
                            tile("Avg. stride", String(format: "%.2f m", stride))
                        }
                        if let watts = metrics.averageCyclingPower {
                            tile("Avg. power", "\(Int(watts.rounded())) W")
                        }
                        if let rpm = metrics.averageCyclingCadence {
                            tile("Avg. cadence", "\(Int(rpm.rounded())) rpm")
                        }
                    }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("detail.health")
            }
        }
        .task(id: activity.id) {
            guard readMetrics, HealthKitService.isSupported else { return }
            metrics = await health.metrics(start: activity.startDate,
                                           end: activity.endDate,
                                           sport: activity.sport)
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
