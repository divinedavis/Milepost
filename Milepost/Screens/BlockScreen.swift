import SwiftData
import SwiftUI

/// The Block tab: your own activities, or your friends'. Called Activities
/// until 2026-09-10.
struct BlockScreen: View {
    enum Feed: String, CaseIterable, Identifiable {
        case mine = "Mine"
        case friends = "Friends"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(SocialStore.self) private var social
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @State private var feed: Feed = .mine
    @State private var path = NavigationPath()

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Show", selection: $feed) {
                    ForEach(Feed.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("block.feed")

                switch feed {
                case .mine: mine
                case .friends: FriendsFeedView(unit: unit) { path.append(FriendsRoute()) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("Wordmark").accessibilityLabel("Milepost")
                }
                if feed == .friends && social.canUseFriends {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { path.append(FriendsRoute()) } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Add friends")
                        .accessibilityIdentifier("block.friends")
                    }
                }
            }
            .navigationDestination(for: Activity.self) { activity in
                ActivityDetailView(activity: activity)
            }
            .navigationDestination(for: FriendsRoute.self) { _ in
                FriendsScreen()
            }
        }
    }

    @ViewBuilder
    private var mine: some View {
        if activities.isEmpty {
            ContentUnavailableView("No activities yet", systemImage: "figure.run",
                                   description: Text("Tap Start on the Record tab and your runs, walks and rides will show up here."))
                .accessibilityIdentifier("block.empty")
        } else {
            List {
                ForEach(activities) { activity in
                    NavigationLink(value: activity) {
                        ActivityRow(activity: activity, unit: unit)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { activities[$0].id }
                    for i in offsets { context.delete(activities[i]) }
                    try? context.save()
                    Task { await social.unshare(ids) }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct ActivityRow: View {
    let activity: Activity
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(activity.title)
                    .font(.headline)
                    .accessibilityIdentifier("block.rowTitle")
            } icon: {
                Image(systemName: activity.sport.symbol)
                    .foregroundStyle(Theme.orange)
                    .accessibilityLabel(activity.sport.title)
            }
            Text(activity.startDate.activityDateText)
                .font(.caption)
                .foregroundStyle(.secondary)
            ActivityStatsLine(distanceMeters: activity.distanceMeters, movingSeconds: activity.movingSeconds,
                              sport: activity.sport, unit: unit)
        }
        .padding(.vertical, 6)
    }
}

/// Distance, pace (or speed on a ride) and time — the same three numbers for
/// your activities and your friends'.
struct ActivityStatsLine: View {
    let distanceMeters: Double
    let movingSeconds: TimeInterval
    let sport: Sport
    let unit: DistanceUnit

    var body: some View {
        HStack(spacing: 24) {
            mini(Format.distance(distanceMeters, unit: unit), unit.abbreviation)
            mini(sport.rateText(Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: movingSeconds, unit: unit, sport: sport), unit: unit),
                 sport.rateSuffix(unit: unit))
            mini(Format.duration(movingSeconds), "time")
        }
    }

    private func mini(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
