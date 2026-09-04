import SwiftData
import SwiftUI

struct YouScreen: View {
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }

    var body: some View {
        NavigationStack {
            List {
                let week = ActivityStats.thisWeek(activities)
                let all = ActivityStats.totals(activities)

                Section("This week") { totals(week) }
                Section("All time") { totals(all) }

                Section("Settings") {
                    Picker("Units", selection: $unitRaw) {
                        ForEach(DistanceUnit.allCases) { u in
                            Text(u.title).tag(u.rawValue)
                        }
                    }
                    .accessibilityIdentifier("you.units")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.versionText)
                    Text("Runs are stored on this phone only. Nothing is uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("You")
        }
    }

    private func totals(_ t: ActivityTotals) -> some View {
        Group {
            LabeledContent("Runs", value: "\(t.count)")
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
