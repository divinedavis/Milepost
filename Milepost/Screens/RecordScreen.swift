import MapKit
import SwiftUI

struct RecordScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(RunRecorder.self) private var recorder
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(Sport.storageKey) private var sportRaw = Sport.run.rawValue
    @Binding var tab: Tab

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showLive = false
    @State private var showSportPicker = false
    @State private var showDenied = false
    @State private var pendingStart = false
    @Namespace private var mapScope

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    /// While a run is live the recorder's own sport wins: the setting could
    /// otherwise be changed from another screen mid-run and relabel the card.
    private var sport: Sport { recorder.isActive ? recorder.sport : (Sport(rawValue: sportRaw) ?? .run) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, scope: mapScope) {
                UserAnnotation()
                if recorder.route.count > 1 {
                    MapPolyline(coordinates: recorder.route.map(\.coordinate))
                        .stroke(Theme.orange, lineWidth: 5)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topTrailing) {
                MapUserLocationButton(scope: mapScope)
                    .buttonBorderShape(.circle)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
            .overlay(alignment: .topLeading) {
                Image("Wordmark")
                    .accessibilityLabel("Milepost")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.card.opacity(0.9), in: Capsule())
                    .padding(.top, 8)
                    .padding(.leading, 12)
            }

            VStack(spacing: 0) {
                statsCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                bottomBar
            }
        }
        .mapScope(mapScope)
        .fullScreenCover(isPresented: $showLive) {
            LiveRecorderView()
        }
        .sheet(isPresented: $showSportPicker) {
            SportPicker(selection: Binding(
                get: { Sport(rawValue: sportRaw) ?? .run },
                set: { sportRaw = $0.rawValue }
            ))
        }
        .alert("Location is off", isPresented: $showDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Milepost needs your location to measure a run. Allow it in Settings.")
        }
        .onChange(of: location.authorization) { _, _ in
            // The user tapped Start before granting; finish what they asked.
            if pendingStart, location.isAuthorized {
                pendingStart = false
                beginRun()
            } else if pendingStart, location.isDenied {
                pendingStart = false
                showDenied = true
            }
        }
    }

    // MARK: Stats card

    private var statsCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Text(sport.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                // Only while a run is live: before Start there is nothing to
                // expand, and the cover would open on 00:00:00 and dismiss itself.
                if recorder.isActive {
                    HStack {
                        Spacer()
                        Button {
                            showLive = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                        .accessibilityLabel("Expand recorder")
                        .accessibilityIdentifier("record.expand")
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                stat(Format.clock(recorder.elapsed), "Time", id: "record.time")
                Spacer()
                stat(sport.rateText(recorder.averagePace, unit: unit),
                     sport.rateLabel("Avg.", unit: unit), id: "record.pace")
                Spacer()
                stat(Format.distance(recorder.distanceMeters, unit: unit), "Distance (\(unit.abbreviation))", id: "record.distance")
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.stat(30))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityIdentifier(id)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color(white: 0.3))
                .frame(width: 56, height: 5)
                .padding(.top, 8)

            if recorder.isActive {
                RecorderControls(layout: .map)
                    .padding(.horizontal, 20)
            } else {
                HStack(alignment: .top) {
                    sportChip
                    Spacer()
                    startButton
                    Spacer()
                    historyChip
                }
                .padding(.horizontal, 36)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
    }

    private var sportChip: some View {
        VStack(spacing: 8) {
            Button { showSportPicker = true } label: {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(white: 0.2))
                        .frame(width: 72, height: 72)
                        .overlay(Image(systemName: sport.symbol).font(.system(size: 28)).foregroundStyle(Theme.orange))
                    Circle()
                        .fill(Theme.orange)
                        .frame(width: 18, height: 18)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sport, \(sport.title)")
            .accessibilityHint("Choose run, walk or ride")
            .accessibilityIdentifier("record.sport")
            Text(sport.title).font(.subheadline).foregroundStyle(.white)
        }
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button(action: startTapped) {
                Circle()
                    .fill(Theme.orange)
                    .frame(width: 88, height: 88)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 34)).foregroundStyle(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start")
            .accessibilityIdentifier("record.start")
            Text("Start").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
        }
    }

    private var historyChip: some View {
        VStack(spacing: 8) {
            Button { tab = .block } label: {
                Circle()
                    .fill(Color(white: 0.2))
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "clock.arrow.circlepath").font(.system(size: 26)).foregroundStyle(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History")
            .accessibilityIdentifier("record.history")
            Text("History").font(.subheadline).foregroundStyle(.white)
        }
    }

    // MARK: Actions

    private func startTapped() {
        if location.isAuthorized {
            beginRun()
        } else if location.isDenied {
            showDenied = true
        } else {
            pendingStart = true
            location.requestPermission()
        }
    }

    private func beginRun() {
        location.startTracking()
        recorder.start(unit: unit, sport: sport)
        showLive = true
    }
}
