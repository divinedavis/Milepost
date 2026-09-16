import SwiftUI

/// Pick a sport and go. Everything else the phone asks about — title, voice
/// cues, sharing — is decided after the fact or not at all on the wrist.
struct WatchStartView: View {
    @Environment(WatchWorkoutController.self) private var workout
    @Environment(WatchPhoneSync.self) private var sync
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(Sport.storageKey) private var sportRaw = Sport.run.rawValue
    @State private var isStarting = false

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var sport: Sport { Sport(rawValue: sportRaw) ?? .run }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Sport.allCases) { option in
                    Button {
                        sportRaw = option.rawValue
                        start(option)
                    } label: {
                        HStack(spacing: 10) {
                            SportIcon(sport: option, size: 20, weight: .semibold)
                                .foregroundStyle(option == sport ? Theme.orange : .primary)
                            Text(option.title)
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("watch.start.\(option.rawValue)")
                }
                .disabled(isStarting)

                if let error = workout.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if workout.location.isDenied {
                    Text("Location is off for Milepost, so distance and pace cannot be measured. Turn it on in the Watch app on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if sync.pendingCount > 0 {
                    Text("\(sync.pendingCount) activity\(sync.pendingCount == 1 ? "" : "s") waiting to reach your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watch.pending")
                }
            }
            .navigationTitle("Milepost")
        }
    }

    private func start(_ sport: Sport) {
        guard !isStarting else { return }
        isStarting = true
        Task {
            if workout.location.isUndetermined { workout.location.requestPermission() }
            await workout.start(sport: sport, unit: unit)
            isStarting = false
        }
    }
}
