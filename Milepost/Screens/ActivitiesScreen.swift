import SwiftData
import SwiftUI

struct ActivitiesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }

    var body: some View {
        NavigationStack {
            Group {
                if activities.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "figure.run",
                                           description: Text("Tap Start on the Record tab and your runs will show up here."))
                        .accessibilityIdentifier("activities.empty")
                } else {
                    List {
                        ForEach(activities) { activity in
                            NavigationLink(value: activity) {
                                ActivityRow(activity: activity, unit: unit)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(activities[i]) }
                            try? context.save()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Activities")
            .navigationDestination(for: Activity.self) { activity in
                ActivityDetailView(activity: activity)
            }
        }
    }
}

struct ActivityRow: View {
    let activity: Activity
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(activity.title)
                .font(.headline)
                .accessibilityIdentifier("activities.rowTitle")
            Text(activity.startDate.activityDateText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                mini(Format.distance(activity.distanceMeters, unit: unit), unit.abbreviation)
                mini(Format.pace(activity.averagePace(unit: unit)), unit.paceSuffix)
                mini(Format.duration(activity.movingSeconds), "time")
            }
        }
        .padding(.vertical, 6)
    }

    private func mini(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
