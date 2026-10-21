import SwiftData
import SwiftUI

/// Pause / Resume / Finish plus the two things Finish can lead to: the
/// "No Movement Detected" alert and the save sheet. Shared by the map card
/// and the full-screen recorder so both behave identically.
struct RecorderControls: View {
    enum Layout { case map, live }

    @Environment(LocationService.self) private var location
    @Environment(RunRecorder.self) private var recorder
    let layout: Layout

    @State private var showNoMovement = false
    @State private var showNoSignal = false
    @State private var pendingSummary: RunSummary?

    /// The map card and the full-screen recorder both host these controls,
    /// and a fullScreenCover does not hide the map's copy from XCUITest, so
    /// each layout gets its own identifiers.
    private var prefix: String { layout == .live ? "live" : "map" }

    var body: some View {
        HStack(spacing: 12) {
            if recorder.state == .recording {
                pill("Pause", symbol: "pause.fill", fill: Theme.accent, text: .white, id: "\(prefix).pause") {
                    recorder.pause()
                }
            } else {
                pill("Resume", symbol: "play.fill", fill: Theme.accent, text: .white, id: "\(prefix).resume") {
                    recorder.resume()
                }
                pill("Finish", symbol: "flag.checkered", fill: .white, text: .black, id: "\(prefix).finish") {
                    finishTapped()
                }
            }
        }
        .alert("No Movement Detected", isPresented: $showNoMovement) {
            Button("Discard", role: .destructive) { discardRun() }
            Button("Resume", role: .cancel) { recorder.resume() }
        } message: {
            Text("This activity cannot be saved because we couldn't detect any change in your location.")
        }
        // No accepted fix and none now: the runner did move, the phone never
        // knew where. A runner standing on a good fix is "No Movement".
        .alert("No GPS Signal Yet", isPresented: $showNoSignal) {
            Button("Discard", role: .destructive) { discardRun() }
            Button("Keep Trying", role: .cancel) { recorder.resume() }
        } message: {
            Text("Your phone hasn't found a GPS signal. Without cell service this can take a few minutes. Stand outside with a clear view of the sky and wait for \"GPS ready\".")
        }
        .sheet(item: $pendingSummary) { summary in
            SaveActivitySheet(summary: summary) { saved in
                pendingSummary = nil
                if saved { endRun() }
            }
            .presentationDetents([.large])
        }
    }

    private func pill(_ title: String, symbol: String, fill: Color, text: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout == .live ? 22 : 16)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func finishTapped() {
        if let summary = recorder.finish() {
            pendingSummary = summary
        } else if recorder.route.isEmpty, location.gpsStatus == .searching {
            showNoSignal = true
        } else {
            showNoMovement = true
        }
    }

    private func discardRun() {
        endRun()
    }

    private func endRun() {
        recorder.discard()
        location.stopTracking()
    }
}

extension RunSummary: Identifiable {
    var id: Date { startDate }
}
