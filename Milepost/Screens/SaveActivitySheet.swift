import SwiftData
import SwiftUI

struct SaveActivitySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue

    let summary: RunSummary
    /// true = saved, false = discarded. Cancelling the sheet calls nothing.
    let onDone: (Bool) -> Void

    @State private var title: String
    @State private var confirmDiscard = false

    init(summary: RunSummary, onDone: @escaping (Bool) -> Void) {
        self.summary = summary
        self.onDone = onDone
        _title = State(initialValue: Format.defaultTitle(for: summary.startDate))
    }

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }

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
                    LabeledContent("Avg. pace", value: "\(Format.pace(Pace.secondsPerUnit(distanceMeters: summary.distanceMeters, seconds: summary.movingSeconds, unit: unit))) \(unit.paceSuffix)")
                    LabeledContent("Splits", value: "\(summary.splits.filter { $0.isComplete(splitMeters: summary.splitMeters) }.count) full")
                }
                Section {
                    Button("Save Run") { save() }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                        .accessibilityIdentifier("save.save")
                }
                Section {
                    Button("Discard Run", role: .destructive) { confirmDiscard = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("save.discard")
                }
            }
            .navigationTitle("Save Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("save.cancel")
                }
            }
            .confirmationDialog("Discard this run?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { onDone(false); dismiss() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = Activity(summary: summary, title: trimmed.isEmpty ? Format.defaultTitle(for: summary.startDate) : trimmed)
        context.insert(activity)
        try? context.save()
        onDone(true)
        dismiss()
    }
}
