import MapKit
import SwiftUI

/// Every saved activity's route as a line on one map, opened from the "Your
/// map" card on Profile (added 2026-10-22, user request, after Airbnb's
/// travel map). Lines are coloured by sport; the chips filter them.
struct RoutesMapView: View {
    @Environment(\.dismiss) private var dismiss
    let activities: [Activity]

    @State private var filter: Sport? = nil
    @State private var lines: [RouteLine] = []
    @State private var position: MapCameraPosition = .automatic

    private var shown: [RouteLine] { lines.filter { filter == nil || $0.sport.mapGroup == filter } }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                ForEach(shown) { line in
                    MapPolyline(coordinates: line.coordinates)
                        .stroke(line.sport.mapColor,
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Text("Your map")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.card.opacity(0.92), in: Capsule())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.card.opacity(0.92), in: Circle())
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("routes.close")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil, title: "All")
                        ForEach(RoutesMapView.groups, id: \.self) { sport in
                            chip(sport, title: sport.mapGroupTitle)
                        }
                    }
                }
                // Presented from Profile, which leaves room for the tab bar.
                .contentMargins(.bottom, 0, for: .scrollContent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack {
                Spacer()
                Text(caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.card.opacity(0.92), in: Capsule())
                    .accessibilityIdentifier("routes.count")
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .task {
            // Decoded once, on the main actor (SwiftData), and thinned: a
            // map of a few hundred hour-long runs is millions of points.
            lines = activities.compactMap(RouteLine.init)
        }
        .onChange(of: filter) { _, _ in
            withAnimation { position = .automatic }
        }
    }

    static let groups: [Sport] = [.run, .walk, .bike]

    private var caption: String {
        if lines.isEmpty { return "Your lines show up here after your first activity" }
        let n = shown.count
        return n == 1 ? "1 activity" : "\(n) activities"
    }

    private func chip(_ sport: Sport?, title: String) -> some View {
        let selected = filter == sport
        return Button { filter = sport } label: {
            HStack(spacing: 6) {
                if let sport {
                    Circle().fill(sport.mapColor).frame(width: 8, height: 8)
                }
                Text(title).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(selected ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Color.white : Theme.card.opacity(0.92), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("routes.filter.\(sport?.rawValue ?? "all")")
    }
}

/// One activity's route, thinned for drawing many at once.
struct RouteLine: Identifiable {
    /// Plenty for a line on a map of a whole city; a route is never drawn
    /// with more.
    static let maxPoints = 250

    let id: UUID
    let sport: Sport
    let coordinates: [CLLocationCoordinate2D]

    init?(_ activity: Activity) {
        let all = activity.coordinates
        guard all.count > 1 else { return nil }
        id = activity.id
        sport = activity.sport
        coordinates = Self.thin(all, to: Self.maxPoints)
    }

    /// Every k-th point, always keeping the last so the line ends where the
    /// activity did. At most `limit + 1` points.
    static func thin(_ points: [CLLocationCoordinate2D], to limit: Int) -> [CLLocationCoordinate2D] {
        guard points.count > limit, limit > 1 else { return points }
        let step = Int((Double(points.count - 1) / Double(limit - 1)).rounded(.up))
        var indices = Array(stride(from: 0, to: points.count, by: step))
        if indices.last != points.count - 1 { indices.append(points.count - 1) }
        return indices.map { points[$0] }
    }
}

extension Sport {
    /// Stroller runs are runs on this map.
    var mapGroup: Sport { self == .strollerRun ? .run : self }

    var mapGroupTitle: String {
        switch mapGroup {
        case .run, .strollerRun: return "Runs"
        case .walk: return "Walks"
        case .bike: return "Rides"
        }
    }

    var mapColor: Color {
        switch mapGroup {
        case .run, .strollerRun: return Theme.accentText
        case .walk: return Color(red: 0.30, green: 0.85, blue: 0.55)
        case .bike: return Color(red: 1.0, green: 0.62, blue: 0.26)
        }
    }
}
