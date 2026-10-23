import MapKit
import SwiftData
import SwiftUI

struct RecordScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(RunRecorder.self) private var recorder
    @Environment(MirroredWorkoutMonitor.self) private var mirror
    @Environment(SocialStore.self) private var social
    @Environment(RunRecovery.self) private var recovery
    @Environment(HolidayStore.self) private var holidays
    /// The three stats follow Dynamic Type (the accessibility audit flagged a
    /// fixed 30 pt); equal-thirds columns + minimumScaleFactor keep them on
    /// one line at the largest sizes.
    @ScaledMetric(relativeTo: .title) private var statSize: CGFloat = 30
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(Sport.storageKey) private var sportRaw = Sport.run.rawValue
    @AppStorage(HeatmapWindow.storageKey) private var heatRaw = HeatmapWindow.default.rawValue
    @Query(sort: \Activity.startDate, order: .reverse) private var activities: [Activity]
    @Binding var tab: Tab

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showLive = false
    @State private var showSportPicker = false
    @State private var showDenied = false
    @State private var pendingStart = false
    /// The Record panel pulled up to show `RecordOptions` (Strava's sheet).
    @State private var showOptions = false
    /// Past routes, coloured by how often each street was covered.
    @State private var heat: [HeatSegment] = []
    /// Friends' shared street cells in the window, for blue and green.
    @State private var friendStreets: [FriendStreets] = []
    @Namespace private var mapScope

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var heatWindow: HeatmapWindow { HeatmapWindow(rawValue: heatRaw) ?? .default }
    private var heatActivities: [Activity] { activities.filter { heatWindow.includes($0.startDate) } }
    /// While a run is live the recorder's own sport wins: the setting could
    /// otherwise be changed from another screen mid-run and relabel the card.
    private var sport: Sport { recorder.isActive ? recorder.sport : (Sport(rawValue: sportRaw) ?? .run) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, scope: mapScope) {
                UserAnnotation()
                ForEach(heat) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if recorder.route.count > 1 {
                    MapPolyline(coordinates: recorder.route.map(\.coordinate))
                        .stroke(Theme.accent, lineWidth: 5)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            // Edge to edge: under the status bar and under the floating
            // dark glass controls and tab bar.
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                MapUserLocationButton(scope: mapScope)
                    .buttonBorderShape(.circle)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Image("Wordmark")
                        .accessibilityLabel("Milepost")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .darkGlass(in: Capsule(), shadow: false)
                    heatWindowMenu
                }
                .padding(.top, 8)
                .padding(.leading, 12)
            }

            VStack(spacing: 0) {
                // While the watch is recording, the phone is a remote for it
                // and its own controls are out of the way.
                MirroredWorkoutBanner()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                if let recovered = recovery.recovered, !recorder.isActive {
                    RecoveredRunBanner(recovered: recovered, unit: unit,
                                       onView: { recovery.recovered = nil; tab = .block },
                                       onDismiss: { recovery.recovered = nil })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                if !mirror.isMirroring {
                    // Always before Start; mid-run only while the signal is missing.
                    if location.isAuthorized && (!recorder.isActive || location.gpsStatus == .searching) {
                        GPSStatusPill(status: location.gpsStatus)
                            .padding(.bottom, 8)
                    }
                    // Only during a workout (owner, 2026-10-22): before Start
                    // it was a card of zeros covering the map.
                    if recorder.isActive {
                        statsCard
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                    }
                    bottomBar
                }
            }
        }
        .mapScope(mapScope)
        .task(id: FriendKey(window: heatWindow, signedIn: social.canUseFriends)) {
            guard heatWindow != .off else { friendStreets = []; return }
            let since = heatWindow.days.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }
            let streets = await social.loadFriendStreets(since: since)
            guard !Task.isCancelled else { return }
            friendStreets = streets
        }
        .task(id: HeatKey(window: heatWindow, ids: heatActivities.map(\.id),
                          friendIDs: friendStreets.map(\.activityID))) {
            // Decoding the stored routes has to happen here (SwiftData
            // models stay on the main actor); the grid work does not.
            let routes = heatActivities.map(\.coordinates)
            let friends = heatWindow == .off ? [] : friendStreets.map { $0.cells.map(RouteHeatmap.unpack) }
            let segments = await Task.detached(priority: .userInitiated) {
                RouteHeatmap.segments(routes: routes, friendStreets: friends)
            }.value
            guard !Task.isCancelled else { return }
            heat = segments
        }
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
        .onAppear { location.warmUp() }
        .onDisappear { location.coolDown() }
        .onChange(of: location.authorization) { _, _ in
            location.warmUp()
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

    // MARK: Heatmap

    private var heatWindowMenu: some View {
        Menu {
            Picker("Show past activities", selection: $heatRaw) {
                ForEach(HeatmapWindow.allCases) { window in
                    Text(window.title).tag(window.rawValue)
                }
            }
            Text("Orange: your streets, darker each time you cover them again.")
            Text("Blue: streets friends shared. Green: streets you both covered.")
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(heatWindow == .off ? Color(white: 0.4) : RouteHeatmap.color(level: 2))
                    .frame(width: 8, height: 8)
                Text(heatWindow == .off ? "Past routes off" : heatWindow.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .darkGlass(in: Capsule(), shadow: false)
        }
        .accessibilityLabel("Past activities, \(heatWindow.title)")
        .accessibilityValue(heatWindow == .off
            ? "0 activities, 0 from friends"
            : "\(heatActivities.count) activities, \(friendStreets.count) from friends")
        .accessibilityIdentifier("record.heatWindow")
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
            // Equal thirds, not Spacers: with Spacers each column is as wide
            // as its own text, so the middle stat slides whenever a
            // neighbour's changes — "Avg. pace (/mi)" to "Avg. speed (mph)",
            // or the distance passing 10.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                stat(Format.clock(recorder.elapsed), "Time", id: "record.time")
                stat(sport.rateText(recorder.averagePace, unit: unit),
                     sport.rateLabel("Avg.", unit: unit), id: "record.pace")
                stat(Format.distance(recorder.distanceMeters, unit: unit), "Distance (\(unit.abbreviation))", id: "record.distance")
            }
        }
        .padding(16)
        .darkGlass(in: RoundedRectangle(cornerRadius: 22))
    }

    private func stat(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.stat(statSize))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityIdentifier(id)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if !recorder.isActive { grabber }
            if recorder.isActive {
                RecorderControls(layout: .map)
                    .padding(.horizontal, 20)
            } else {
                // Equal thirds, not Spacers. With Spacers every column was
                // as wide as its own label, so picking Stroller Run — a
                // label wider than both the circle above it and "History" —
                // grew the left column and shoved Start off centre. Thirds
                // put Start on the screen's centre line whatever is chosen.
                HStack(alignment: .center, spacing: 0) {
                    sportChip
                    startButton
                    historyChip
                }
                .padding(.horizontal, 24)
                if showOptions {
                    RecordOptions()
                        .padding(.horizontal, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.top, recorder.isActive ? 18 : 8)
        .padding(.bottom, 18)
        // Pull up for more, push down to put it away, anywhere on the panel.
        .contentShape(RoundedRectangle(cornerRadius: 30))
        .gesture(DragGesture(minimumDistance: 14).onEnded { drag in
            guard !recorder.isActive else { return }
            if drag.translation.height < -30 { setOptions(true) }
            if drag.translation.height > 30 { setOptions(false) }
        })
        .onChange(of: recorder.isActive) { _, active in
            if active { showOptions = false }
        }
        .frame(maxWidth: .infinity)
        // A floating dark glass panel (2026-10-22) instead of an opaque
        // sheet, so the map and its past routes fill the screen.
        .darkGlass(in: RoundedRectangle(cornerRadius: 30))
        .overlay {
            if let holiday = holidays.current, !recorder.isActive {
                HolidayRim(holiday: holiday, cornerRadius: 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// The handle on top of the panel. A button as well as a drag target, so
    /// VoiceOver and a plain tap can open it too.
    private var grabber: some View {
        Button { setOptions(!showOptions) } label: {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showOptions ? "Hide options" : "More options")
        .accessibilityValue(showOptions ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("record.moreOptions")
    }

    private func setOptions(_ show: Bool) {
        guard show != showOptions else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { showOptions = show }
    }

    private var sportChip: some View {
        VStack(spacing: 8) {
            Button { showSportPicker = true } label: {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 72, height: 72)
                        .overlay(SportIcon(sport: sport, size: 28).foregroundStyle(Theme.accent))
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 18, height: 18)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sport, \(sport.title)")
            .accessibilityHint("Choose run, stroller run, walk or ride")
            .accessibilityIdentifier("record.sport")
        }
        .modifier(ControlColumn())
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button(action: startTapped) {
                Group {
                    if let holiday = holidays.current {
                        // The day's colours, darkened a touch so the white
                        // play mark keeps its contrast on light ones.
                        Circle()
                            .fill(AngularGradient(colors: holiday.tabColors + [holiday.tabColors.first ?? .white], center: .center))
                            .overlay(Circle().fill(Color.black.opacity(0.18)))
                            .shadow(color: holiday.glow.opacity(0.6), radius: 14)
                    } else {
                        Circle().fill(Theme.accent)
                    }
                }
                .frame(width: 88, height: 88)
                .overlay(Image(systemName: "play.fill").font(.system(size: 34)).foregroundStyle(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start")
            .accessibilityValue(holidays.current.map { "\($0.name) theme" } ?? "")
            .accessibilityIdentifier("record.start")
        }
        .modifier(ControlColumn())
    }

    private var historyChip: some View {
        VStack(spacing: 8) {
            Button { tab = .block } label: {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "clock.arrow.circlepath").font(.system(size: 26)).foregroundStyle(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History")
            .accessibilityIdentifier("record.history")
        }
        .modifier(ControlColumn())
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
        recorder.start(unit: unit, sport: sport, autoPause: AutoPauseSettings.isEnabled())
        showLive = true
    }
}

/// "Finding GPS" until a fix is good enough to record with. Without cell
/// service that can take minutes, and a run started before it shows 0.00.
struct GPSStatusPill: View {
    let status: GPSStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status == .ready ? Color.green : Theme.paused)
                .frame(width: 8, height: 8)
            Text(status == .ready ? "GPS ready" : "Finding GPS…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // Opaque and without the glass rim: see-through glass over a light
        // map failed the contrast audit (1.6 ship, 2026-10-22), and so did the
        // opaque glass colour with its light rim (the audit read the rim as
        // the background). This exact pill passed before dark glass.
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gps.status")
    }
}

/// Shown once after a launch that rescued the previous process's run: the
/// app died mid-activity and the last autosave became a saved activity. A
/// card, not an alert — nothing is asked, it only says what happened.
struct RecoveredRunBanner: View {
    let recovered: RunRecovery.Recovered
    let unit: DistanceUnit
    let onView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("We saved your \(recovered.sport.title.lowercased())")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Milepost closed before you finished. \(Format.distance(recovered.distanceMeters, unit: unit)) \(unit.abbreviation) were kept, up to the moment it stopped.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("View in Block", action: onView)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.top, 2)
                    .accessibilityIdentifier("record.recoveredView")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("record.recovered")
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(6)
            }
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("record.recoveredDismiss")
        }
        .padding(14)
        .darkGlass(in: RoundedRectangle(cornerRadius: 16))
    }
}

/// What the heatmap is drawn from; a new id list or window recomputes it.
private struct HeatKey: Hashable {
    let window: HeatmapWindow
    let ids: [UUID]
    let friendIDs: [UUID]
}

/// When to fetch friends' streets again.
private struct FriendKey: Hashable {
    let window: HeatmapWindow
    let signedIn: Bool
}

/// One of the three columns under the map. Each takes exactly a third of the
/// row so the Start button sits on the screen's centre line no matter how
/// long the sport's name is; a name too long for its third shrinks rather
/// than widening the column and moving everything else.
private struct ControlColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }
}

/// A ring of the day's colours turning slowly round the Record panel, with a
/// soft glow (Marracat's search-bar rim). Still with Reduce Motion on.
private struct HolidayRim: View {
    let holiday: Holiday
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        let colors = holiday.tabColors + [holiday.tabColors.first ?? .white]
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(AngularGradient(colors: colors, center: .center, angle: .degrees(angle)), lineWidth: 2)
            .shadow(color: holiday.glow.opacity(0.55), radius: 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}
