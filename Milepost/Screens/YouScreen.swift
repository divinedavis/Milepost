import MapKit
import SwiftData
import SwiftUI

/// Where a Profile row leads. Settings, Apple Health and the account each
/// got their own screen on 2026-10-22, when Profile took Airbnb's layout: a
/// header card, a map card, two tiles, then rows.
enum ProfileRoute: Hashable {
    case settings, health, account
}

/// The Profile tab (called You until 2026-10-22; ids keep the `you.` prefix
/// and the tab its `you` raw value, so links and tests still resolve).
struct YouScreen: View {
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(HealthSettings.dailyKey) private var dailySteps = HealthSettings.dailyDefault
    @Environment(SocialStore.self) private var social
    @Binding var tab: Tab

    @State private var path = NavigationPath()
    @State private var showMap = false

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Group {
                    header
                    mapCard
                    tiles
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if dailySteps, HealthKitService.isSupported {
                    DailyMovementSection(unit: unit)
                }

                Section("This week") { totals(ActivityStats.thisWeek(activities)) }

                Section {
                    row("Settings", symbol: "gearshape", id: "you.rowSettings") { path.append(ProfileRoute.settings) }
                    row("Apple Health", symbol: "heart", id: "you.rowHealth") { path.append(ProfileRoute.health) }
                    row("Friends & account", symbol: "person", id: "you.rowAccount") { path.append(ProfileRoute.account) }
                    Link(destination: URL(string: "https://divinedavis.com/milepost/support/")!) {
                        rowLabel("Get help", symbol: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://divinedavis.com/milepost/privacy/")!) {
                        rowLabel("Privacy", symbol: "hand.raised")
                    }
                } footer: {
                    Text("Milepost \(Self.versionText). Routes are stored on this phone only.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { bell }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .settings: SettingsScreen()
                case .health: List { HealthSection() }.navigationTitle("Apple Health")
                case .account: List { AccountSection() }.navigationTitle("Friends & account")
                }
            }
            .navigationDestination(for: FriendsRoute.self) { _ in FriendsScreen() }
            // Keeps the bell and the Friends tile's badge current.
            .task(id: social.canUseFriends) { await social.loadConnections() }
            .task(id: social.openRequests) {
                guard social.openRequests else { return }
                social.openRequests = false
                path = NavigationPath([FriendsRoute()])
            }
            .fullScreenCover(isPresented: $showMap) {
                RoutesMapView(activities: activities)
            }
        }
        .clearsTabBar()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(spacing: 8) {
                ProfileAvatar(initials: initials, size: 88)
                Text(name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("you.name")
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                headerStat("\(activities.count)", activities.count == 1 ? "Activity" : "Activities", id: "you.statActivities")
                Divider().padding(.vertical, 8)
                headerStat(Format.distance(ActivityStats.totals(activities).distanceMeters, unit: unit),
                           unit == .miles ? "Miles" : "Kilometres", id: "you.statDistance")
                Divider().padding(.vertical, 8)
                headerStat(tenure.value, tenure.label, id: "you.statTenure")
            }
            .frame(width: 120)
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func headerStat(_ value: String, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var name: String {
        if let profile = social.profile { return profile.name }
        return "You"
    }

    private var subtitle: String {
        social.profile?.handle ?? "Milepost"
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty || name == "You" ? "" : letters.uppercased()
    }

    /// "12 Weeks on Milepost", Airbnb's "Years on Airbnb", from the first
    /// activity. Days until a week has passed, years after two.
    private var tenure: (value: String, label: String) {
        guard let first = activities.last?.startDate else { return ("0", "Days on Milepost") }
        let days = max(0, Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0)
        switch days {
        case ..<7: return ("\(days)", days == 1 ? "Day on Milepost" : "Days on Milepost")
        case ..<730:
            let weeks = days / 7
            return ("\(weeks)", weeks == 1 ? "Week on Milepost" : "Weeks on Milepost")
        default: return ("\(days / 365)", "Years on Milepost")
        }
    }

    // MARK: Map card

    private var mapCard: some View {
        Button { showMap = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your map")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Every street you've walked, run and ridden, drawn as lines.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                ProfileMapPreview(activities: Array(activities.prefix(40)))
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your map")
        .accessibilityHint("Shows every route you've recorded")
        .accessibilityIdentifier("you.map")
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 12) {
            tile("Activities", symbol: "list.bullet.rectangle", badge: nil, id: "you.tileActivities") {
                tab = .block
            }
            tile("Friends", symbol: "person.2", badge: social.incoming.count, id: "you.tileFriends") {
                openFriends()
            }
        }
    }

    private func tile(_ title: String, symbol: String, badge: Int?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(height: 40)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text("\(badge) new")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // A deeper red than .red: white on system red is ~3.5:1
                        // at this size and failed the contrast audit.
                        .background(Color(red: 0.80, green: 0.0, blue: 0.08), in: Capsule())
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { $0 > 0 ? "\(title), \($0) new" : title } ?? title)
        .accessibilityIdentifier(id)
    }

    /// Friends when signed in, otherwise the account screen to sign in on.
    /// Appended as their own types: wrapped in AnyHashable they match no
    /// navigationDestination and the tap does nothing.
    private func openFriends() {
        if social.canUseFriends {
            path.append(FriendsRoute())
        } else {
            path.append(ProfileRoute.account)
        }
    }

    // MARK: Bell

    private var bell: some View {
        Button {
            openFriends()
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                    if !social.incoming.isEmpty {
                        Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(social.incoming.isEmpty ? "Notifications" : "Notifications, \(social.incomingSummary)")
        .accessibilityIdentifier("you.notifications")
    }

    // MARK: Rows

    private func row(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                rowLabel(title, symbol: symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityIdentifier(id)
    }

    private func rowLabel(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).foregroundStyle(.white)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.white)
        }
    }

    private func totals(_ t: ActivityTotals) -> some View {
        Group {
            LabeledContent("Activities", value: "\(t.count)")
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

/// Initials on the accent, or a runner when there is no name to take them from.
struct ProfileAvatar: View {
    let initials: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "figure.run")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The small map on the card: the newest routes, framed to fit.
private struct ProfileMapPreview: View {
    @Environment(HealthKitService.self) private var health
    let activities: [Activity]
    @State private var lines: [RouteLine] = []
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, interactionModes: []) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(line.sport.mapColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay {
            if lines.isEmpty {
                Text("Your lines show up here after your first activity.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    // Opaque: over the map a see-through card failed the
                    // contrast audit. The card's button already says what
                    // this is, so VoiceOver skips it.
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .accessibilityHidden(true)
            }
        }
        // Keyed on the ids so a new activity redraws, but not every render.
        .task(id: activities.map(\.id)) {
            await health.refreshMapRoutes()
            drawLines()
        }
        // The switch in Apple Health settings turned on or off.
        .onChange(of: health.mapRoutes.map(\.id)) { _, _ in drawLines() }
    }

    /// The newest of each, like the activities this card is given.
    private func drawLines() {
        lines = RouteLine.all(activities: activities, health: Array(health.mapRoutes.prefix(40)))
        // .automatic frames the content present when it is set.
        position = .automatic
    }
}
