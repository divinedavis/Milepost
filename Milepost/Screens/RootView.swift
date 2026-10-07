import SwiftUI

enum Tab: String, CaseIterable {
    case record, block, you

    var title: String {
        switch self {
        case .record: return "Record"
        case .block: return "Block"
        case .you: return "You"
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
                case .you: YouScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.background)
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
                        Text(item.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(tab == item ? Theme.accentText : Theme.secondaryText)
                }
                .accessibilityIdentifier("tab.\(item.rawValue)")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(Theme.card)
        .overlay(alignment: .top) { Divider() }
    }
}
