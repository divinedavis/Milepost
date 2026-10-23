import SwiftUI

/// Steps and walking distance per day, from Apple Health, at the top of the
/// You tab (added 2026-10-22, user request). Health already holds what the
/// iPhone and an Apple Watch counted all day, recorded in Milepost or not,
/// so this reads it rather than counting anything itself. Shown only once
/// "Daily steps" is on in the Apple Health section.
struct DailyMovementSection: View {
    static let dayCount = 7

    @Environment(HealthKitService.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    let unit: DistanceUnit

    @State private var days: [DailyMovement] = []
    @State private var loaded = false

    var body: some View {
        Section {
            if let today = days.first {
                todayRow(today)
                ForEach(days.dropFirst()) { day in
                    LabeledContent(day.day.formatted(.dateTime.weekday(.wide)),
                                   value: summary(day))
                        .accessibilityIdentifier("you.dailyDay")
                }
            } else if loaded {
                Text("Nothing from Apple Health yet.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("Daily steps")
        } footer: {
            Text(footer)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            days = await load()
            loaded = true
        }
    }

    private func todayRow(_ today: DailyMovement) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stepsText(today.steps))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("steps today").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(distanceText(today.distanceMeters))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("walked today").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("you.dailyToday")
    }

    private var footer: String {
        let empty = loaded && days.allSatisfy { $0.steps == nil && $0.distanceMeters == nil }
        if empty {
            return "If this stays empty, allow Milepost to read Steps and Walking + Running Distance in Health > Sharing > Apps > Milepost."
        }
        return "Counted all day by your iPhone and Apple Watch, whether or not Milepost was recording. Health merges the two so no step is counted twice. Stays on this phone."
    }

    private func summary(_ day: DailyMovement) -> String {
        guard day.steps != nil || day.distanceMeters != nil else { return "--" }
        return "\(stepsText(day.steps)) · \(distanceText(day.distanceMeters))"
    }

    private func stepsText(_ steps: Double?) -> String {
        steps.map { Int($0.rounded()).formatted() } ?? "--"
    }

    private func distanceText(_ meters: Double?) -> String {
        meters.map { "\(Format.distance($0, unit: unit)) \(unit.abbreviation)" } ?? "--"
    }

    private func load() async -> [DailyMovement] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-daily-demo") {
            return Self.demo()
        }
        #endif
        return await health.dailyMovement(days: Self.dayCount)
    }

    #if DEBUG
    /// A week of plausible numbers, with yesterday empty (watch off, phone
    /// left at home), so the UI can be driven without a Health database.
    static func demo(now: Date = .now) -> [DailyMovement] {
        let steps: [Double] = [6_412, 0, 11_870, 4_205, 9_034, 7_760, 12_301]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var s: [Date: Double] = [:], d: [Date: Double] = [:]
        for (i, count) in steps.enumerated() where count > 0 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            s[day] = count
            d[day] = count * 0.74
        }
        return DailyMovement.days(dayCount, endingOn: now, steps: s, distance: d)
    }
    #endif
}
