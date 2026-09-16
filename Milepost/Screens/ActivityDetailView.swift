import MapKit
import SwiftData
import SwiftUI

struct ActivityDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(HealthSettings.enabledKey) private var healthEnabled = HealthSettings.enabledDefault
    @AppStorage(HealthSettings.routeKey) private var healthRoute = HealthSettings.routeDefault
    @Bindable var activity: Activity
    @State private var confirmDelete = false
    @State private var editingTitle = false
    @State private var draftTitle = ""

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var coordinates: [CLLocationCoordinate2D] { activity.coordinates }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                routeMap
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.title).font(.title2.bold())
                        .accessibilityIdentifier("detail.title")
                    Text(activity.startDate.activityDateText).font(.subheadline).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    tile("Distance", "\(Format.distance(activity.distanceMeters, unit: unit)) \(unit.abbreviation)")
                    tile("Moving time", Format.duration(activity.movingSeconds))
                    tile("Avg. \(activity.sport.rateNoun)",
                         "\(activity.sport.rateText(activity.averagePace(unit: unit), unit: unit)) \(activity.sport.rateSuffix(unit: unit))")
                    tile("Elapsed", Format.duration(activity.endDate.timeIntervalSince(activity.startDate)))
                }

                HealthMetricsSection(activity: activity)

                splitsSection
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(activity.sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        draftTitle = activity.title
                        editingTitle = true
                    }
                    .accessibilityIdentifier("detail.rename")
                    if healthEnabled, HealthKitService.isSupported, !activity.isInAppleHealth {
                        Button("Save to Apple Health", systemImage: "heart") {
                            Task { await HealthSync.write(activity, using: health, context: context, includeRoute: healthRoute) }
                        }
                        .accessibilityIdentifier("detail.saveToHealth")
                    }
                    Button("Delete \(activity.sport.title)", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("detail.delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("detail.menu")
            }
        }
        .confirmationDialog("Delete this \(activity.sport.title.lowercased())?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Health first: once SwiftData has dropped the row there is no
                // workout id left to delete with.
                let health = health
                let activity = activity
                Task { await HealthSync.remove(activity, using: health) }
                context.delete(activity)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename \(activity.sport.title)", isPresented: $editingTitle) {
            TextField("Title", text: $draftTitle)
                .accessibilityIdentifier("detail.renameField")
            Button("Save") {
                let t = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { activity.title = t; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var routeMap: some View {
        if coordinates.count > 1, let rect = RouteGeometry.fittedRect(coordinates) {
            Map(initialPosition: .rect(rect), interactionModes: [.pan, .zoom]) {
                MapPolyline(coordinates: coordinates).stroke(Theme.orange, lineWidth: 5)
                if let first = coordinates.first {
                    Annotation("Start", coordinate: first, anchor: .center) {
                        Circle().fill(.green).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
                if let last = coordinates.last {
                    Annotation("Finish", coordinate: last, anchor: .center) {
                        Circle().fill(.red).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        } else {
            ZStack {
                Theme.card
                Label("No route recorded", systemImage: "map").foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var splitsSection: some View {
        let recorded = activity.recordedUnit
        let sport = activity.sport
        let splits = activity.splits
        if !splits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Splits (\(recorded.abbreviation))").font(.headline)
                let paces = splits.compactMap { $0.pace(unit: recorded, sport: sport) }
                let fastest = paces.min() ?? 0
                let slowest = paces.max() ?? 0
                ForEach(splits) { split in
                    let complete = split.isComplete(splitMeters: activity.splitMeters)
                    HStack(spacing: 12) {
                        Text(complete ? "\(split.index)" : String(format: "%.2f", split.distanceMeters / recorded.meters))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(complete ? Theme.orange : Theme.splitBlue)
                                .frame(width: geo.size.width * width(for: split.pace(unit: recorded, sport: sport), fastest: fastest, slowest: slowest))
                        }
                        .frame(height: 14)
                        Text(sport.rateText(split.pace(unit: recorded, sport: sport), unit: recorded))
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("detail.split.\(split.index)")
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func width(for pace: Double?, fastest: Double, slowest: Double) -> CGFloat {
        guard let pace else { return 0.3 }
        guard slowest > fastest else { return 1 }
        return 0.4 + 0.6 * CGFloat((slowest - pace) / (slowest - fastest))
    }
}

enum RouteGeometry {
    /// A map rect around the route with a little breathing room; nil when
    /// there is nothing to frame.
    static func fittedRect(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        var rect = MKMapRect.null
        for c in coordinates {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 1, height: 1)))
        }
        let padW = max(rect.size.width * 0.25, 200)
        let padH = max(rect.size.height * 0.25, 200)
        return rect.insetBy(dx: -padW, dy: -padH)
    }
}
