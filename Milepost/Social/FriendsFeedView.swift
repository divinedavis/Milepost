import SwiftUI

/// The Friends half of the Block tab.
struct FriendsFeedView: View {
    @Environment(SocialStore.self) private var social
    let unit: DistanceUnit
    let onFindFriends: () -> Void

    @State private var showSetup = false
    @State private var reporting: FeedActivity?
    @State private var blocking: FeedActivity?

    var body: some View {
        Group {
            switch social.phase {
            case .restoring:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInCard()
            case .signedIn:
                if let error = social.profileError, !social.profileLoaded {
                    unreachable(error) { await social.loadProfile() }
                } else if !social.profileLoaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if social.profile == nil {
                    usernamePrompt
                } else {
                    feed
                }
            }
        }
        .sheet(isPresented: $showSetup) { UsernameSetupSheet() }
    }

    private var usernamePrompt: some View {
        ContentUnavailableView {
            Label("Pick a username", systemImage: "at")
        } description: {
            Text("Friends find you by your username.")
        } actions: {
            Button("Choose a username") { showSetup = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("friends.pickUsername")
        }
    }

    private func unreachable(_ error: String, retry: @escaping () async -> Void) -> some View {
        ContentUnavailableView {
            Label("Can't reach friends", systemImage: "wifi.slash")
        } description: {
            Text(error)
        } actions: {
            Button("Try again") { Task { await retry() } }
        }
    }

    @ViewBuilder
    private var feed: some View {
        Group {
            if social.feed.isEmpty {
                if let error = social.feedError {
                    unreachable(error) { await social.loadFeed() }
                } else if !social.feedLoaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No friend activity yet", systemImage: "person.2")
                    } description: {
                        Text("Add friends by username. Their runs, walks and rides show up here — the stats, never the map.")
                    } actions: {
                        Button("Find friends", action: onFindFriends)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("friends.find")
                    }
                }
            } else {
                List(social.feed) { item in
                    FriendActivityRow(item: item, unit: unit)
                        .swipeActions {
                            Button("Block", role: .destructive) { blocking = item }
                            Button("Report") { reporting = item }.tint(.orange)
                        }
                        .contextMenu {
                            Button("Report", systemImage: "flag") { reporting = item }
                            Button("Block \(item.handle)", systemImage: "hand.raised", role: .destructive) { blocking = item }
                        }
                }
                .listStyle(.plain)
                .refreshable { await social.loadFeed() }
            }
        }
        .task { await social.loadFeed() }
        .confirmationDialog("Report this activity?", isPresented: present($reporting), titleVisibility: .visible, presenting: reporting) { item in
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) { Task { await social.report(item.userID, activityID: item.activityID, reason: reason) } }
            }
        }
        .confirmationDialog("Block \(blocking?.handle ?? "")?", isPresented: present($blocking), titleVisibility: .visible, presenting: blocking) { item in
            Button("Block", role: .destructive) { Task { await social.block(item.userID) } }
        } message: { _ in
            Text("They stop being your friend, can't find you, and can't send you requests. Unblock from Friends.")
        }
        .alert(social.notice ?? "", isPresented: noticeShown) { Button("OK") {} }
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { social.notice != nil }, set: { if !$0 { social.notice = nil } })
    }
}

/// `isPresented` for a sheet or dialog driven by an optional.
func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
    Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
}

struct FriendActivityRow: View {
    let item: FeedActivity
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("friends.rowName")
                if !item.displayName.isEmpty {
                    Text(item.handle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Label {
                Text(item.title)
                    .font(.headline)
                    .accessibilityIdentifier("friends.rowTitle")
            } icon: {
                Image(systemName: item.sport.symbol)
                    .foregroundStyle(Theme.orange)
                    .accessibilityLabel(item.sport.title)
            }
            Text(item.startDate.activityDateText)
                .font(.caption)
                .foregroundStyle(.secondary)
            ActivityStatsLine(distanceMeters: item.distanceMeters, movingSeconds: item.movingSeconds,
                              sport: item.sport, unit: unit)
        }
        .padding(.vertical, 6)
    }
}
