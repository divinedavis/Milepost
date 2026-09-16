import Foundation
import SwiftData

/// The one path from a saved activity into Apple Health, so the save sheet and
/// the "save this one too" button on an older activity cannot drift apart.
@MainActor
enum HealthSync {
    /// Writes the activity to Health and records the workout's id on it.
    /// Already-written activities are skipped rather than duplicated.
    /// Failure is deliberately quiet: the activity is saved either way and the
    /// Health switch on the You tab shows what went wrong.
    @discardableResult
    static func write(_ activity: Activity,
                      using health: HealthKitService,
                      context: ModelContext,
                      includeRoute: Bool) async -> Bool {
        guard HealthKitService.isSupported, health.canWriteWorkouts else { return false }
        guard activity.healthWorkoutID == nil else { return true }
        do {
            let id = try await health.save(summary: activity.summary,
                                           title: activity.title,
                                           activityID: activity.id,
                                           includeRoute: includeRoute)
            activity.healthWorkoutID = id.uuidString
            try? context.save()
            return true
        } catch {
            return false
        }
    }

    /// Called when an activity is deleted in Milepost. Health only lets an app
    /// delete samples it wrote itself, so this never touches a workout that
    /// came from the Watch or another app.
    static func remove(_ activity: Activity, using health: HealthKitService) async {
        guard let raw = activity.healthWorkoutID, let id = UUID(uuidString: raw) else { return }
        await health.deleteWorkout(id: id)
    }
}
