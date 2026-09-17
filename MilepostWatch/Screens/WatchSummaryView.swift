import SwiftUI

/// What the run came to, and where it went. The watch has already written the
/// workout to Health by the time this appears; the phone copy is queued and may
/// still be in flight, which the footer says plainly rather than implying the
/// activity is lost.
struct WatchSummaryView: View {
    @Environment(WatchWorkoutController.self) private var workout
    @Environment(WatchPhoneSync.self) private var sync

    var body: some View {
        NavigationStack {
            List {
                if let payload = workout.finished {
                    let unit: DistanceUnit = abs(payload.splitMeters - DistanceUnit.kilometers.meters) < 1 ? .kilometers : .miles
                    Section {
                        row("Distance", "\(Format.distance(payload.distanceMeters, unit: unit)) \(unit.abbreviation)")
                        row("Time", Format.duration(payload.movingSeconds))
                        row(payload.sport.showsSpeed ? "Avg. speed" : "Avg. pace",
                            "\(payload.sport.rateText(Pace.secondsPerUnit(distanceMeters: payload.distanceMeters, seconds: payload.movingSeconds, unit: unit, sport: payload.sport), unit: unit)) \(payload.sport.rateSuffix(unit: unit))")
                        if let fastest = payload.splits.fastestPace(splitMeters: payload.splitMeters, unit: unit, sport: payload.sport) {
                            row("Fastest \(unit.splitNoun.lowercased())",
                                "\(payload.sport.rateText(fastest, unit: unit)) \(payload.sport.rateSuffix(unit: unit))")
                        }
                        if let climb = SplitTimeline.elevationAscended(route: payload.route) {
                            row("Elevation gain", "\(Format.elevation(climb, unit: unit)) \(unit.elevationAbbreviation)")
                        }
                        if let bpm = payload.averageHeartRate {
                            row("Avg. heart rate", "\(Int(bpm.rounded())) bpm")
                        }
                        if let kcal = payload.activeKilocalories {
                            row("Active calories", "\(Int(kcal.rounded())) kcal")
                        }
                    } header: {
                        Text(payload.title)
                    } footer: {
                        Text(footer(for: payload))
                            .accessibilityIdentifier("watch.summary.footer")
                    }
                } else {
                    Text("That one was too short to save.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Done") { workout.clearFinished() }
                    .accessibilityIdentifier("watch.done")
            }
            .navigationTitle("Saved")
        }
    }

    private func footer(for payload: WatchActivityPayload) -> String {
        var lines: [String] = []
        lines.append(payload.healthWorkoutID == nil
                     ? "Not written to Apple Health."
                     : "Saved to Apple Health.")
        lines.append(sync.pendingCount > 0
                     ? "It will appear on your iPhone the next time they are in range."
                     : "Sent to your iPhone.")
        return lines.joined(separator: " ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.weight(.semibold)).monospacedDigit()
        }
    }
}
