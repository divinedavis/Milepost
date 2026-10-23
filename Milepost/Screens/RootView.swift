import SwiftUI

enum Tab: String, CaseIterable {
    case record, block, you

    var title: String {
        switch self {
        case .record: return "Record"
        case .block: return "Block"
        case .you: return "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .record: return "record.circle"
        case .block: return "list.bullet.rectangle"
        case .you: return "person.crop.circle"
        }
    }
}

struct RootView: View {
    @Environment(RunRecorder.self) private var recorder
    @Environment(SaveCelebration.self) private var celebration
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var scenePhase
    /// UI tests share one demo backend with a waiting request; the banner
    /// would sit over every Friends test, so only its own test turns it on.
    private let checksRequests: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return !args.contains("-uitest") || args.contains("-uitest-request-banner")
    }()
    // `-open-tab block` lets scripts land on a tab for screenshots.
    @State private var tab: Tab = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-open-tab"), i + 1 < args.count, let t = Tab(rawValue: args[i + 1]) { return t }
        return .record
    }()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .record: RecordScreen(tab: $tab)
                case .block: BlockScreen()
                case .you: YouScreen(tab: $tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            if let person = social.requestBanner {
                FriendRequestBanner(person: person) {
                    social.requestBanner = nil
                    social.openRequests = true
                    tab = .you
                } onDismiss: {
                    withAnimation { social.requestBanner = nil }
                }
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.spring(duration: 0.35), value: social.requestBanner?.id)
        // While the app is open and signed in: look for new friend requests
        // now and every minute. Leaving the foreground cancels the loop.
        .task(id: TaskKey(active: scenePhase == .active, signedIn: social.canUseFriends)) {
            guard checksRequests, scenePhase == .active, social.canUseFriends else { return }
            while !Task.isCancelled {
                await social.checkForRequests()
                try? await Task.sleep(for: .seconds(SocialStore.requestCheckInterval))
            }
        }
        .task(id: social.requestBanner?.id) {
            // The banner leaves on its own after a few seconds.
            guard social.requestBanner != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation { social.requestBanner = nil }
        }
        // An overlay, not a cover: Save dismisses the sheet and the live
        // recorder's cover at the same moment, and presenting a third one
        // mid-dismissal is dropped. The overlay is revealed as they slide away.
        .overlay {
            if let moment = celebration.moment {
                CelebrationView(moment: moment) {
                    withAnimation(.easeOut(duration: 0.25)) { celebration.moment = nil }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    /// Hand-rolled: iOS 26's floating TabView bar reports a successful tap in
    /// XCUITest without switching, and this one is three buttons anyway.
    private var tabBar: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 20))
                            .overlay(alignment: .topTrailing) {
                                if item == .you, !social.incoming.isEmpty {
                                    Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 4, y: -2)
                                }
                            }
                        Text(item.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(tab == item ? Theme.accentText : Theme.secondaryText)
                }
                .accessibilityIdentifier("tab.\(item.rawValue)")
                .accessibilityValue(item == .you && !social.incoming.isEmpty ? social.incomingSummary : "")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(Theme.card)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct TaskKey: Hashable {
    let active: Bool
    let signedIn: Bool
}

/// "Sam sent you a friend request", dropped in from the top of any tab.
/// In-app only: Milepost has no push notifications.
struct FriendRequestBanner: View {
    let person: FriendProfile
    let onView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(initials: String(person.name.prefix(1)).uppercased(), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(person.name) sent you a friend request")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(person.handle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            Button("View", action: onView)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("request.view")
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.secondaryText)
            }
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("request.dismiss")
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("request.banner")
    }
}
