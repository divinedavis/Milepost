import SwiftData
import SwiftUI

struct SaveActivitySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @Environment(SaveCelebration.self) private var celebration
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue

    let summary: RunSummary
    /// true = saved, false = discarded. Cancelling the sheet calls nothing.
    let onDone: (Bool) -> Void

    @State private var title: String
    @State private var confirmDiscard = false

    init(summary: RunSummary, onDone: @escaping (Bool) -> Void) {
        self.summary = summary
        self.onDone = onDone
        _title = State(initialValue: Format.defaultTitle(for: summary.startDate, sport: summary.sport))
    }

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var sport: Sport { summary.sport }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("save.title")
                }
                Section("Summary") {
                    LabeledContent("Distance", value: "\(Format.distance(summary.distanceMeters, unit: unit)) \(unit.abbreviation)")
                    LabeledContent("Moving time", value: Format.duration(summary.movingSeconds))
                    LabeledContent(sport.rateLabel("Avg.", unit: unit).replacingOccurrences(of: " (\(sport.rateSuffix(unit: unit)))", with: ""),
                                   value: "\(sport.rateText(Pace.secondsPerUnit(distanceMeters: summary.distanceMeters, seconds: summary.movingSeconds, unit: unit, sport: sport), unit: unit)) \(sport.rateSuffix(unit: unit))")
                    LabeledContent("Splits", value: "\(summary.splits.filter { $0.isComplete(splitMeters: summary.splitMeters) }.count) full")
                }
                Section {
                    Button("Save \(sport.title)") { save() }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                        .accessibilityIdentifier("save.save")
                }
                Section {
                    Button("Discard \(sport.title)", role: .destructive) { confirmDiscard = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("save.discard")
                }
            }
            .navigationTitle("Save \(sport.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("save.cancel")
                }
            }
            .confirmationDialog("Discard this \(sport.title.lowercased())?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { onDone(false); dismiss() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = Activity(summary: summary, title: trimmed.isEmpty ? Format.defaultTitle(for: summary.startDate, sport: sport) : trimmed)
        context.insert(activity)
        try? context.save()
        // Stats only, and only when signed in with sharing on; a failed
        // upload is retried by the next session's syncAll.
        Task { await social.share(activity) }
        celebration.celebrate(title: activity.title, summary: summary)
        onDone(true)
        dismiss()
    }
}
