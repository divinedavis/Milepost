import SwiftUI

/// Run / Stroller Run / Walk / Ride. Opened by tapping the sport chip on the Record tab;
/// only reachable before a run starts, so nothing can change mid-recording.
struct SportPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Sport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Sport.allCases) { sport in
                        Button {
                            selection = sport
                            dismiss()
                        } label: {
                            row(sport)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sport.\(sport.rawValue)")
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("sport.cancel")
                }
            }
        }
        .presentationDetents([.height(440), .large])
        .preferredColorScheme(.dark)
    }

    private func row(_ sport: Sport) -> some View {
        let isSelected = sport == selection
        return HStack(spacing: 14) {
            Circle()
                .fill(isSelected ? Theme.accent : Color(white: 0.2))
                .frame(width: 52, height: 52)
                .overlay(
                    SportIcon(sport: sport, size: 22)
                        .foregroundStyle(isSelected ? .white : Theme.accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(sport.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(sport.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
