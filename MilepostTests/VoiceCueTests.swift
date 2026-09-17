import CoreLocation
import XCTest
@testable import Milepost

@MainActor
final class VoiceCueTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private static let baseLatitude = 40.68
    private static let metersPerDegree: Double = {
        let a = CLLocation(latitude: baseLatitude, longitude: -73.97)
        let b = CLLocation(latitude: baseLatitude + 0.01, longitude: -73.97)
        return b.distance(from: a) * 100
    }()

    private func fix(_ metersNorth: Double, at seconds: TimeInterval) -> CLLocation {
        let lat = Self.baseLatitude + metersNorth / Self.metersPerDegree
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -73.97),
                          altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                          course: 0, speed: -1,
                          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    private func recorder(collecting into: @escaping (Milestone) -> Void) -> RunRecorder {
        let r = RunRecorder(now: { [unowned self] in self.clock })
        r.onMilestone = into
        return r
    }

    // MARK: Engine

    func testHalfUnitBoundaryFiresOnceWithProRatedTime() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .miles)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(360)
        r.ingest(fix(900, at: 360))                    // 6:00 for 900 m, crosses 804.67 m
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0].distanceMeters, DistanceUnit.miles.meters / 2, accuracy: 0.001)
        XCTAssertEqual(seen[0].units, 0.5)
        XCTAssertEqual(seen[0].elapsed, 360 * (804.672 / 900), accuracy: 1)
        XCTAssertEqual(seen[0].unit, .miles)
        // The next fix short of the mile fires nothing more.
        clock = clock.addingTimeInterval(60)
        r.ingest(fix(1000, at: 420))
        XCTAssertEqual(seen.count, 1)
    }

    func testOneLongStepEmitsEveryBoundaryInOrder() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(600)
        r.ingest(fix(1700, at: 600))
        XCTAssertEqual(seen.map(\.units), [0.5, 1, 1.5])
        XCTAssertEqual(seen[0].elapsed, 600 * 500 / 1700, accuracy: 1)
        XCTAssertEqual(seen[1].elapsed, 600 * 1000 / 1700, accuracy: 1)
        XCTAssertEqual(seen[2].elapsed, 600 * 1500 / 1700, accuracy: 1)
        XCTAssertEqual(seen[1].averagePace!, 600 * 1000 / 1700, accuracy: 2)
    }

    func testMilestonesRestartOnEachRun() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(200)
        r.ingest(fix(600, at: 200))
        XCTAssertEqual(seen.map(\.units), [0.5])
        r.discard()
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 300))
        clock = clock.addingTimeInterval(200)
        r.ingest(fix(600, at: 500))
        XCTAssertEqual(seen.map(\.units), [0.5, 0.5], "A new run counts from zero again")
    }

    // MARK: Setting

    func testIntervalFilter() {
        XCTAssertFalse(VoiceCueInterval.off.includes(units: 1))
        XCTAssertFalse(VoiceCueInterval.full.includes(units: 0.5))
        XCTAssertTrue(VoiceCueInterval.full.includes(units: 1))
        XCTAssertTrue(VoiceCueInterval.full.includes(units: 3))
        XCTAssertTrue(VoiceCueInterval.half.includes(units: 0.5))
        XCTAssertTrue(VoiceCueInterval.half.includes(units: 2))
    }

    func testTitlesFollowTheUnit() {
        XCTAssertEqual(VoiceCueInterval.half.title(unit: .miles), "Every half mile")
        XCTAssertEqual(VoiceCueInterval.full.title(unit: .kilometers), "Every kilometer")
        XCTAssertEqual(VoiceCueInterval.off.title(unit: .kilometers), "Off")
    }

    func testLongerIntervalsOnlyIncludeMatchingDistances() {
        let boundaries = stride(from: 0.5, through: 10.0, by: 0.5)
        XCTAssertEqual(boundaries.filter { VoiceCueInterval.two.includes(units: $0) }, [2, 4, 6, 8, 10])
        XCTAssertEqual(boundaries.filter { VoiceCueInterval.five.includes(units: $0) }, [5, 10])
        XCTAssertFalse(VoiceCueInterval.half.includes(units: 0))
        XCTAssertFalse(VoiceCueInterval.half.includes(units: .nan))
        XCTAssertEqual(VoiceCueInterval.two.title(unit: .miles), "Every 2 miles")
        XCTAssertEqual(VoiceCueInterval.five.title(unit: .kilometers), "Every 5 kilometers")
    }

    func testSettingsMigrationAndLiveChanges() {
        let suite = "VoiceCueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let announcer = VoiceAnnouncer(defaults: defaults, isMuted: true)
        XCTAssertTrue(announcer.isEnabled)
        XCTAssertEqual(announcer.interval, .half)

        defaults.set(VoiceCueInterval.two.rawValue, forKey: VoiceCueInterval.storageKey)
        defaults.set(false, forKey: VoiceCueInterval.enabledKey)
        XCTAssertFalse(announcer.isEnabled)
        XCTAssertEqual(announcer.interval, .two)
        defaults.set(true, forKey: VoiceCueInterval.enabledKey)
        XCTAssertTrue(announcer.isEnabled)
        XCTAssertEqual(announcer.interval, .two, "Toggling must remember the interval")

        let relaunched = VoiceAnnouncer(defaults: defaults, isMuted: true)
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertEqual(relaunched.interval, .two)
    }

    func testMigrationPreservesLegacyOffAndIntervalSelections() {
        let suite = "VoiceCueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for previous in [VoiceCueInterval.off, .half, .full] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(previous.rawValue, forKey: VoiceCueInterval.storageKey)
            VoiceCueInterval.migrateSettings(in: defaults)
            XCTAssertEqual(defaults.bool(forKey: VoiceCueInterval.enabledKey), previous != .off)
            XCTAssertEqual(defaults.string(forKey: VoiceCueInterval.storageKey),
                           (previous == .off ? VoiceCueInterval.half : previous).rawValue)
            VoiceCueInterval.migrateSettings(in: defaults)
            XCTAssertEqual(defaults.bool(forKey: VoiceCueInterval.enabledKey), previous != .off,
                           "Launching again must not turn voice back on")
        }
    }

    func testPreviewUsesSelectedDistanceAndUnits() {
        let sample = VoiceAnnouncer.sample(unit: .kilometers, interval: .five)
        XCTAssertEqual(sample.units, 5)
        XCTAssertTrue(VoiceCuePhrase.text(for: sample).hasPrefix("5 kilometers complete."))
        let half = VoiceAnnouncer.sample(unit: .miles, interval: .half)
        XCTAssertTrue(VoiceCuePhrase.text(for: half).hasPrefix("Half a mile complete."))
    }

    func testPausedDistanceDoesNotAnnounceAndResumeDoesNotRepeat() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(200)
        r.ingest(fix(600, at: 200))
        XCTAssertEqual(seen.map(\.units), [0.5])
        r.pause()
        r.ingest(fix(1600, at: 400))
        XCTAssertEqual(seen.map(\.units), [0.5])
        clock = clock.addingTimeInterval(200)
        r.resume()
        r.ingest(fix(1600, at: 400))
        clock = clock.addingTimeInterval(200)
        r.ingest(fix(2200, at: 600))
        XCTAssertEqual(seen.map(\.units), [0.5, 1])
        r.discard()
    }

    // MARK: Phrase

    func testPhraseForEachDistanceShape() {
        XCTAssertEqual(VoiceCuePhrase.distance(0.5, unit: .miles), "Half a mile complete.")
        XCTAssertEqual(VoiceCuePhrase.distance(1, unit: .miles), "1 mile complete.")
        XCTAssertEqual(VoiceCuePhrase.distance(1.5, unit: .miles), "1 and a half miles complete.")
        XCTAssertEqual(VoiceCuePhrase.distance(3, unit: .kilometers), "3 kilometers complete.")
        XCTAssertEqual(VoiceCuePhrase.distance(2.5, unit: .kilometers), "2 and a half kilometers complete.")
    }

    func testSpokenDurations() {
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 45), "45 seconds")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 60), "1 minute")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 9 * 60 + 5), "9 minutes 5 seconds")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 3600 + 120), "1 hour 2 minutes")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 0), "0 seconds")
    }

    // MARK: Recorded voice

    func testScriptStitchesTheSameWordsAsThePhrase() {
        let mile = Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 9 * 60 + 12, unit: .miles)
        XCTAssertEqual(VoiceCueScript.clips(for: mile),
                       ["dist_mi_1", "phrase_time", "num_9", "word_minutes", "num_12", "word_seconds",
                        "phrase_avg_pace", "num_9", "word_minutes", "num_12", "word_seconds", "unit_per_mi"])
        let jitter = Milestone(distanceMeters: DistanceUnit.miles.meters / 2, elapsed: 30, unit: .miles)
        XCTAssertEqual(VoiceCueScript.clips(for: jitter), ["dist_mi_0h", "phrase_time", "num_30", "word_seconds"])
        let long = Milestone(distanceMeters: DistanceUnit.kilometers.meters * 10.5, elapsed: 3600 + 60, unit: .kilometers)
        XCTAssertEqual(VoiceCueScript.clips(for: long)!.prefix(5),
                       ["dist_km_10h", "phrase_time", "num_1", "word_hour", "num_1"])
        let ride = Milestone(distanceMeters: DistanceUnit.miles.meters * 2, elapsed: 2 * 3600 / 14.2, unit: .miles, sport: .bike)
        XCTAssertEqual(VoiceCueScript.clips(for: ride)!.suffix(5),
                       ["phrase_avg_speed", "num_14", "word_point", "num_2", "unit_mph"])
        // Spoken text and clip text say the same words, so the fallback says
        // the same thing (the number/word clips carry no sentence punctuation).
        let library = VoiceCueScript.library
        let words = { (text: String) in text.filter { !".,".contains($0) } }
        let stitched = VoiceCueScript.clips(for: mile)!.map { library[$0]! }.joined(separator: " ")
        XCTAssertEqual(words(stitched), words(VoiceCuePhrase.text(for: mile)))
    }

    func testScriptGivesUpPastTheLibrary() {
        let ultra = Milestone(distanceMeters: DistanceUnit.miles.meters * 31, elapsed: 5 * 3600, unit: .miles)
        XCTAssertNil(VoiceCueScript.clips(for: ultra), "past 30 miles the system voice takes over")
        XCTAssertNotNil(VoiceCueScript.clips(for: Milestone(distanceMeters: DistanceUnit.miles.meters * 30, elapsed: 5 * 3600, unit: .miles)))
        XCTAssertNotNil(VoiceCueScript.clips(for: Milestone(distanceMeters: DistanceUnit.kilometers.meters * 50, elapsed: 5 * 3600, unit: .kilometers)))
    }

    /// The render script and the Swift library are two copies of one list.
    /// This is what catches them drifting, and a clip that never got rendered.
    func testEveryClipInTheLibraryIsBundled() throws {
        let bundle = Bundle(for: RunRecorder.self)
        let url = try XCTUnwrap(bundle.url(forResource: VoiceCueScript.manifestName, withExtension: "json"),
                                "VoiceCues.json missing: run scripts/make_voice_cues.py")
        let manifest = try JSONDecoder().decode(VoiceCueScript.Manifest.self, from: Data(contentsOf: url))
        let library = VoiceCueScript.library
        XCTAssertEqual(Set(manifest.clips.keys), Set(library.keys), "make_voice_cues.py and VoiceCueScript.library disagree")
        for (name, text) in library {
            XCTAssertEqual(manifest.clips[name], text, "\(name) was rendered from different text")
            XCTAssertNotNil(bundle.url(forResource: VoiceCueScript.clipPrefix + name, withExtension: "mp3"), "\(name).mp3 not in the bundle")
        }
        XCTAssertEqual(library.count, 236)
    }

    func testAnnouncerPrefersTheRecordedVoiceAndFallsBackPastIt() {
        let defaults = UserDefaults(suiteName: "VoiceCueTests.announcer")!
        defaults.removePersistentDomain(forName: "VoiceCueTests.announcer")
        let announcer = VoiceAnnouncer(defaults: defaults, bundle: Bundle(for: RunRecorder.self), isMuted: true)
        XCTAssertTrue(announcer.hasRecordedVoice)
        announcer.announce(Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 9 * 60 + 12, unit: .miles))
        XCTAssertEqual(announcer.lastCue, .clips(VoiceCueScript.clips(for: Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 9 * 60 + 12, unit: .miles))!))
        announcer.announce(Milestone(distanceMeters: DistanceUnit.miles.meters * 31, elapsed: 5 * 3600, unit: .miles))
        XCTAssertEqual(announcer.lastCue, .synthesized("31 miles complete. Time, 5 hours. Average pace, 9 minutes 41 seconds per mile."))
        // Every clip the preview can ask for is on hand, for both units.
        for unit in DistanceUnit.allCases {
            for interval in VoiceCueInterval.selectable {
                announcer.play(VoiceAnnouncer.sample(unit: unit, interval: interval))
                if case .synthesized = announcer.lastCue { XCTFail("preview for \(unit) \(interval) fell back to the system voice") }
            }
        }
    }

    func testFullPhraseIncludesPaceOnlyWhenPlausible() {
        let mile = Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 9 * 60 + 12, unit: .miles)
        XCTAssertEqual(VoiceCuePhrase.text(for: mile),
                       "1 mile complete. Time, 9 minutes 12 seconds. Average pace, 9 minutes 12 seconds per mile.")
        let jitter = Milestone(distanceMeters: DistanceUnit.miles.meters / 2, elapsed: 30, unit: .miles)
        XCTAssertEqual(VoiceCuePhrase.text(for: jitter), "Half a mile complete. Time, 30 seconds.")
    }
}
