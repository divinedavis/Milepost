import SwiftUI

/// Pushed from the Block tab's Friends feed and from You.
struct FriendsRoute: Hashable {}

/// Find people by username, answer requests, manage friends and blocks.
struct FriendsScreen: View {
    @Environment(SocialStore.self) private var social
    @State private var query = ""
    @State private var results: [FriendProfile] = []
    @State private var searched = false
    /// The server's own words when a search fails (e.g. the 60-per-10-minute
    /// limit), so a refusal never reads as "No one by that username".
    @State private var searchError: String?
    @State private var reporting: FriendProfile?
    @State private var blocking: FriendProfile?

    private var needle: String { Username.normalize(query) }
    private var reportTitle: String { "Report \(reporting?.handle ?? "")?" }
    private var blockTitle: String { "Block \(blocking?.handle ?? "")?" }
    private var noticeShown: Binding<Bool> {
        Binding(get: { social.notice != nil }, set: { if !$0 { social.notice = nil } })
    }

    var body: some View {
        List {
            searchSection
            requestsSection
            friendsSection
            sentSection
            blockedSection
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await social.loadConnections()
            social.markRequestsSeen()
        }
        .task(id: needle) { await runSearch() }
        .refreshable { await social.loadConnections() }
        .confirmationDialog(reportTitle, isPresented: present($reporting), titleVisibility: .visible, presenting: reporting) { person in
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) { Task { await social.report(person.id, activityID: nil, reason: reason) } }
            }
        }
        .confirmationDialog(blockTitle, isPresented: present($blocking), titleVisibility: .visible, presenting: blocking) { person in
            Button("Block", role: .destructive) {
                Task {
                    await social.block(person.id)
                    results.removeAll { $0.id == person.id }
                }
            }
        } message: { _ in
            Text("They stop being your friend, can't find you, and can't send you requests.")
        }
        .alert(social.notice ?? "", isPresented: noticeShown) {
            Button("OK") {}
        }
    }

    // The sections are separate properties: as one body the type checker
    // took 2.9 s on every build (2026-10-24 slow-compile report).
    @ViewBuilder
    private var searchSection: some View {
        Section {
            TextField("Search by username", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("friends.search")
            ForEach(results) { person in
                PersonRow(person: person) { searchControl(person) }
            }
            if let searchError {
                Text(searchError).foregroundStyle(.secondary)
                    .accessibilityIdentifier("friends.searchError")
            } else if searched && results.isEmpty && needle.count >= 3 {
                Text("No one by that username.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Add friends")
        } footer: {
            Text("Friends see the stats of what you share — never your routes.")
        }
    }

    @ViewBuilder
    private var requestsSection: some View {
        if !social.incoming.isEmpty {
            Section("Requests") {
                ForEach(social.incoming) { person in
                    PersonRow(person: person) {
                        HStack(spacing: 8) {
                            Button("Accept") { Task { await social.respond(to: person.id, accept: true) } }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("friends.accept.\(person.username)")
                            Button("Decline") { Task { await social.respond(to: person.id, accept: false) } }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("friends.decline.\(person.username)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        if !social.friends.isEmpty {
            Section("Friends") {
                ForEach(social.friends) { person in
                    PersonRow(person: person) { EmptyView() }
                        .accessibilityIdentifier("friends.friend.\(person.username)")
                        .swipeActions {
                            Button("Remove", role: .destructive) { Task { await social.remove(person.id) } }
                            Button("Block") { blocking = person }.tint(.gray)
                        }
                        .contextMenu {
                            Button("Report", systemImage: "flag") { reporting = person }
                            Button("Block", systemImage: "hand.raised", role: .destructive) { blocking = person }
                            Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                                Task { await social.remove(person.id) }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var sentSection: some View {
        if !social.outgoing.isEmpty {
            Section("Sent") {
                ForEach(social.outgoing) { person in
                    PersonRow(person: person) {
                        Button("Cancel") { Task { await social.remove(person.id) } }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("friends.cancel.\(person.username)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var blockedSection: some View {
        if !social.blocked.isEmpty {
            Section("Blocked") {
                ForEach(social.blocked) { person in
                    PersonRow(person: person) {
                        Button("Unblock") { Task { await social.unblock(person.id) } }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("friends.unblock.\(person.username)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchControl(_ person: FriendProfile) -> some View {
        switch person.status {
        case .none:
            Button("Add") {
                Task {
                    if let status = await social.sendRequest(to: person.id) { setStatus(person.id, status) }
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("friends.add.\(person.username)")
        case .outgoing:
            Text("Requested")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("friends.status.\(person.username)")
        case .incoming:
            Button("Accept") {
                Task {
                    await social.respond(to: person.id, accept: true)
                    setStatus(person.id, .friend)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("friends.accept.\(person.username)")
        case .friend:
            Text("Friends")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("friends.status.\(person.username)")
        }
    }

    private func setStatus(_ id: UUID, _ status: FriendStatus) {
        if let i = results.firstIndex(where: { $0.id == id }) { results[i].status = status }
    }

    private func runSearch() async {
        let q = needle
        // The server refuses prefixes under 3 characters (usernames are 3+).
        guard q.count >= 3 else {
            results = []
            searched = false
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        social.lastError = nil
        let found = await social.search(q)
        guard !Task.isCancelled else { return }
        results = found
        searchError = social.lastError
        social.lastError = nil
        searched = true
    }
}

struct PersonRow<Trailing: View>: View {
    let person: FriendProfile
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.body.weight(.semibold))
                if !person.displayName.isEmpty {
                    Text(person.handle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}
