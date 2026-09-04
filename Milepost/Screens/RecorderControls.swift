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
    @State private var pendingSummary: RunSummary?

    var body: some View {
        HStack(spacing: 12) {
            if recorder.state == .recording {
                pill("Pause", symbol: "pause.fill", fill: Theme.orange, text: .white, id: "recorder.pause") {
                    recorder.pause()
                }
            } else {
                pill("Resume", symbol: "play.fill", fill: Theme.orange, text: .white, id: "recorder.resume") {
                    recorder.resume()
                }
                pill("Finish", symbol: "flag.checkered", fill: .white, text: .black, id: "recorder.finish") {
                    finishTapped()
                }
            }
        }
        .alert("No Movement Detected", isPresented: $showNoMovement) {
            Button("Discard", role: .destructive) { discardRun() }
            Button("Resume") { recorder.resume() }
        } message: {
            Text("This activity cannot be saved because we couldn't detect any change in your location.")
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
