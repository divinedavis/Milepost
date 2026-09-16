# Milepost — working notes

A Strava-style tracker for runs, stroller runs, walks and bike rides: GPS record screen,
full-screen live recorder
(time / split pace / distance / splits), pause + resume, "No Movement
Detected" guard, save to a local SwiftData log, per-run detail with route map,
and a Dynamic Island / lock-screen Live Activity showing the mile in progress.
Recording needs no account. The optional friends layer (Block > Friends) is
the only thing with a backend, and routes never go to it — see "Friends".

Same per-change loop as the other iOS apps (Pothole Radar is the template):

1. `./scripts/run_tests.sh` — unit + UI. Decide whether the change needs a new
   XCUITest and say so in the commit body ("XCUITest: added X" / "N/A because").
   The suite is five passes: unit, static UI, sport, Live Activity, and two
   moving ones (a run at 3.5 m/s and a ride at 8 m/s).
2. `./scripts/smoke_test.sh` — a green suite does not prove a cold launch.
3. Secrets scan of the staged diff. `scripts/asc-config.env` and `*.p8` are
   gitignored; nothing else here is secret.
4. OWASP LLM note in the commit: always N/A, there is no LLM surface.
5. Commit with an explanatory body + `Co-Authored-By`, then push.
6. `./scripts/ship.sh` for app-code changes once the ASC app record exists.

Gotchas:
- `project.yml` is the source of truth; never hand-edit the pbxproj. Run
  `./scripts/generate.sh` after adding files — a build with a stale project
  silently produces empty test bundles.
- Resources live under `sources:` on purpose; XcodeGen drops a `resources:` key.
- Background recording relies on `UIBackgroundModes: location` +
  `allowsBackgroundLocationUpdates`. Removing either kills tracking with the
  screen off, with no error (the first one traps at runtime).
- UI tests pass `-uitest` → in-memory SwiftData store. `run_tests.sh` pins the
  simulator at a fixed Brooklyn location for `MilepostUITests` (every run ends
  in "No Movement Detected") and starts a `simctl location` route through
  Prospect Park for `MilepostRouteUITests` (distance must climb, save works).
- `run_tests.sh ui <filter>` takes `Target/Class/test`. `MilepostUITests/testX`
  resolves to a class that does not exist and runs zero tests; so does a
  freshly generated project whose test bundle has not been rebuilt. xcodebuild
  prints `** TEST SUCCEEDED **` either way, so `run_tests.sh` now fails with
  "NO TESTS RAN" unless the log says tests actually executed. If you see that,
  the filter is wrong or the xcodeproj is stale.
- Offscreen `List` cells are not in the accessibility tree. The Settings
  section on You sits below the fold on an iPhone 17 Pro: `app.swipeUp()`
  before querying it, or the element "does not exist".
- `-uitest` wipes UserDefaults on launch; tests do not need to restore settings.
- Two simulators can share the name "iPhone 17 Pro" (26.4 and 26.5 runtimes);
  `simctl io "iPhone 17 Pro" screenshot` may hit the one the tests are not on.
- The tab bar is hand-rolled (iOS 26 TabView taps lie to XCUITest).

Sports (`Sport.swift`, `SportPicker`):
- Run / Stroller Run / Walk / Ride, chosen from the chip on the Record tab, remembered in
  UserDefaults. The chip is only on screen before a run starts, so the sport
  cannot change mid-recording; `RecordScreen.sport` reads the recorder's own
  value while one is live in case the setting is changed elsewhere.
- The engine is identical for all sports. What differs is the plausibility
  window and the wording. A 45-minute mile is a normal walk and outside the
  run bounds; 36 mph is a normal descent on a bike and outside them too. Get
  this wrong and the rate silently reads "-:--" for a whole activity.
- A ride reads in **speed** (mph / km/h), a run and a walk in **pace**
  (min/mi). `Sport.rateText` / `rateSuffix` / `rateLabel` are the only place
  that decides; do not call `Format.pace` directly in a view.
- `Sport` is compiled into the widget, so it cannot touch app-only types.
  That is why the spoken-duration helper lives on `Format` and
  `VoiceCuePhrase.spoken` is a thin alias to it.
- `SportIcon` draws the shared activity mark in the app and widget. Stroller
  running uses a custom vector runner pushing a stroller and the run pace bounds.
- `Activity.sportRaw` was added after 1.0 shipped, with a default, so
  SwiftData migrates existing stored runs without a mapping model. Do not
  make it non-optional without a default.

Friends (`Milepost/Social/`, `supabase/migrations/`, added 2026-09-10):
- The Activities tab is now **Block**, with a Mine / Friends switch. `Tab.block`,
  ids `tab.block`, `block.rowTitle`, `block.empty`; `-open-tab block`.
- Backend: Supabase `pmdcwgsxxyagmkkypvma` (org Juniper, us-east-1, ≈$10/mo).
  Keychain: `milepost-supabase-anon`, `milepost-supabase-service`,
  `milepost-supabase-db-password`; PAT `supabase-pat-clockin`. Anon key goes
  in the gitignored `Secrets.xcconfig` (see `.example`); without it the build
  works and Friends says it is unavailable.
- Migrations go through `POST /v1/projects/<ref>/database/query` (non-default
  User-Agent), then `scripts/e2e_backend.py` must pass — it drives three real
  JWT users through every rule, including the negative ones.
- **Routes never leave the phone.** `shared_activities` has sport, title,
  start, distance, moving time and nothing else; `SharedActivityPayload` is the
  only thing that uploads, and `SocialTests.testSharedPayloadIsStatsOnly` pins
  its keys. Adding a location column is a privacy-policy change, not a feature.
- Sport raw values are `run`/`strollerRun`/`walk`/**`bike`** (not "ride"); the table's check
  must match `Sport.rawValue` or every ride upload is refused.
- All friendship writes are RPCs (`send_friend_request`, `respond_friend_request`,
  `remove_friend`, `block_user`); clients only SELECT `friendships`. Strangers'
  profiles are invisible to RLS — search goes through `search_profiles`
  (definer, ≥2 chars, ≤20 rows, LIKE-escaped, block-aware). Every function
  revokes EXECUTE from public, anon AND authenticated before granting back.
- Sign in with Apple only (email auth off). Nonce: hash to Apple, raw to
  GoTrue, and only when the token carries the claim. `APPLE_ID_AUTH` is on the
  App ID (`scripts/asc_enable_capability.py`); the entitlement is in project.yml.
- Sharing is on by default once signed in; `syncAll` upserts every local
  activity at each session start (also the retry for offline saves). A local
  delete deletes the shared row, or queues it (`social.pendingDeletes`).
  Turning sharing off deletes everything shared.
- App Review has no second account, so `@milepost_demo` (`demo_accounts`
  table, service-role only) auto-accepts requests and carries sample
  activities. Re-run `scripts/seed_demo_friend.py` before a submission so its
  activities are recent. The trigger keys on the id in `demo_accounts`, never
  the username, so nobody can squat the name into auto-accept.
- UI tests: the runner cannot keep a Supabase session (no keychain) or drive
  Apple's sheet, so `-uitest-social-demo` (Debug only) swaps in
  `DemoSocialBackend`. A plain `.tap()` on the Mine/Friends segment reports
  success and selects nothing (same iOS 26 quirk as the tab bar); use
  `selectSegment`, which coordinate-taps and confirms `isSelected`. The
  toolbar button is labelled "Add friends" so it never collides with the
  segment. Text with an accessibility identifier is not found by label via
  `staticTexts["…"]` — match `label ==` with a predicate.
- App Privacy is no longer "Data Not Collected" — `asc_push_privacy_iris.py`
  now declares the friends data (needs a fresh `fastlane spaceauth`, a human).
- Reports land in `public.reports`; nothing alerts on them yet — check the
  table before each release.
- Abuse ceilings live in the database (0003): 20,000 shared activities per
  account, 200 reports per reporter per day, 100 pending outgoing requests.
  Nothing else bounds what a valid session can insert.

Live Activity (`MilepostWidget/`, `RunActivityController`):
- The SwiftData model is called `Activity`, so inside the app target it
  shadows ActivityKit's. Write `ActivityKit.Activity<RunActivityAttributes>`
  or the compiler says "cannot specialize non-generic type 'Activity'".
- `NSSupportsLiveActivities` goes in the **app's** Info.plist, not the
  extension's. Without it `Activity.request` throws and a run just has no card.
- The extension cannot link the app, so `RunActivityAttributes.swift`,
  `Units.swift` and `Theme.swift` are listed under both targets in
  `project.yml` on purpose. Anything the card needs has to be app-independent.
- Never put a value in `ContentState` that moves without a GPS fix. The run
  average pace does (it divides by a ticking `elapsed`), so it made every 1 Hz
  tick a push; the card uses the last *completed* split's pace instead.
  `RunActivityTests.testStateIsStableAcrossTicksThatChangeNothingVisible`
  is the guard.
- The clock is a `Text(timerInterval:)` counting from `recorder.elapsedAnchor`,
  so it ticks inside the widget with no updates from the app. Pausing swaps it
  for a frozen string.
- SpringBoard draws the island, so XCUITest queries `com.apple.springboard`,
  not the app. Two false-positive traps: the home screen behind it has a
  "Milepost" app icon, so `CONTAINS "Milepost"` and `CONTAINS "mi"` both pass
  with no card on screen. Assert on something only the card has ("Mile 1",
  "0.00 mi", "Time").
- The compact island only has room for the mile. Distance, pace and the track
  are expanded-only: long-press at normalized `dy: 0.037` (~32 pt down an
  874 pt screen) to open it. Pressing the status bar above it does nothing.
- The compact island shows **how far**, not which mile: a mile number sits
  there unchanged for a whole mile and reads as frozen. Distance is the
  headline on the expanded card too, with the mile and pace under it. Two
  decimals under ten units, one above, so the compact string stays short.
- Since 2026-09-11 (user request) the expanded island and the lock-screen
  card copy the system **Now Playing** layout, row for row: sport tile where
  the artwork goes, distance + "Mile N · pace" as title/subtitle, a live
  indicator where the sound bars go; the progress line through the mile in
  the scrubber row (clock left, "−0.63 mi" to the next milepost right, like
  time left); Pause / Resume alone at the centre of the bottom row.
- **Height cap: a third-party expanded island (and lock-screen card) is 160 pt
  max; anything past it is clipped with no error.** Music is a system app
  and runs ~207 pt, so "the same size" can only mean the same rows in the
  same places. The first Now Playing build used a 64 pt tile and a 48 pt
  controls row and lost the Pause button off the bottom; the UI test still
  passed because the clipped button kept its accessibility element. Check
  the `island-expanded` screenshot after any layout change
  (`TEST_RUNNER_MILEPOST_SHOTS=<dir> run_tests.sh ui
  MilepostUITests/MilepostLiveActivityUITests`).
- Pause / Resume on the card is a `LiveActivityIntent`. That kind of intent
  runs in the **app's** process (the system wakes the app in the background
  for it), which is the only reason it can reach the live recorder. The
  intent file is compiled into the widget too, so it must not touch the
  engine: the app registers a closure on `RunActivityActions` at launch and
  the intent calls that. If the app was killed the recorder is idle and the
  tap does nothing, which is right — the run is gone either way.
- XCUITest can tap those buttons: they carry accessibility identifiers into
  SpringBoard's tree, so `springboard.buttons["island.pause"]` works.
- A crash mid-run would strand a card nobody owns, so the controller ends any
  stray activity on launch.
- Never `app.debugDescription` or an untyped `descendants(matching: .any)` on
  the Record tab — the MapKit accessibility tree takes minutes to walk.
- `RunRecorder` is the whole engine and is clock-injected; every rule
  (accuracy gate, stationary gate, split roll-over, paused time) has a unit
  test. Change a rule → change its test.
- Splits are stored in the unit the run was recorded with (`splitMeters`);
  the detail view labels them from that, not from the current setting.

Apple Health (`Milepost/Services/HealthKit*`, `HealthSync`, `HealthSection`, added 2026-09-16):
- **Both switches start off.** `HealthSettings.enabledDefault` and `.routeDefault`
  are false, and `HealthTests.testHealthAndRouteWritingAreBothOffByDefault` pins
  them. Saving stats and handing over a map of where the user runs are two
  different promises; the route toggle only appears once saving is on.
- Writing goes through `HKWorkoutBuilder`: distance under the sport's type
  (`distanceCycling` for a ride, `distanceWalkingRunning` otherwise), estimated
  active energy, pause/resume events, and a `.lap` event per completed split.
  Health derives a workout's **duration from the pause events** — leave them out
  and Health shows elapsed time where Milepost shows moving time.
- The route builder must be taken off the workout builder with
  `seriesBuilder(for: HKSeriesType.workoutRoute())`. A standalone
  `HKWorkoutRouteBuilder` finished by hand orphans the route. The watch is the
  exception: it makes its own and calls `finishRoute(with:)` itself.
- `RoutePoint` gained `altitude`, `horizontalAccuracy`, `verticalAccuracy`,
  `speed` and `cumulativeMeters`, all **optional** so activities stored before
  Health decode unchanged. HealthKit drops a route point whose horizontal
  accuracy is not positive, so a legacy point reports
  `RunRecorder.maxHorizontalAccuracy` — the worst fix the engine would have
  accepted, an honest upper bound rather than a flattering guess.
- `cumulativeMeters` is the recorder's own booked distance at that fix, not
  something to re-derive: measuring consecutive route points would count the
  ground covered while paused, because no points are appended during a pause but
  the two either side of it can be far apart. `SplitTimeline` interpolates lap
  boundaries from it, and returns **nothing** for a legacy route rather than
  spacing laps evenly and claiming a precision that is fictional.
- Elevation ignores fixes with a negative `verticalAccuracy` (no altitude
  reading) and rises under a metre (a barometer wanders standing still; summing
  that noise over an hour invents hundreds of feet).
- Calories are modelled, never measured, on the phone: ACSM walking/running
  equations, Compendium MET bands for cycling, minus one MET because Health's
  Move ring counts energy *above* resting. Out-of-bounds speeds produce nil —
  a nonsense number written to Health is worse than no number.
- Reads are by **date range**, not against a stored workout, so a run recorded
  on the phone still shows the heart rate an Apple Watch was recording at the
  same time, whoever wrote the workout. Health never reports whether a read was
  granted; a denied type simply returns nothing.
- `Sport+HealthKit.swift` is separate from `Sport.swift` on purpose: `Sport` is
  compiled into the widget and must not drag HealthKit in with it.
- App Privacy is unchanged. A HealthKit write stays on the user's device and is
  not "collected" by the developer, so nothing new is declared.

Apple Watch (`MilepostWatch/`, added 2026-09-16):
- Single-target watchOS app, `com.divinedavis.milepost.watchkitapp`, watchOS 10+,
  embedded by the iOS app (`Embed Watch Content`). `WKRunsIndependentlyOfCompanionApp`
  is true: it records with no phone nearby.
- **Two engines, on purpose.** `HKWorkoutSession` owns the session — it is the
  only thing that keeps the app alive with the wrist down, and the only source
  of heart rate and active energy. `RunRecorder`, the app's own unchanged
  engine, owns distance, pace and splits from GPS, so a mile split on the watch
  is computed by exactly the same rules as one on the phone.
- Therefore `disableCollection(for:)` is called for **both** distance types on
  the `HKLiveWorkoutDataSource`. Leave automatic collection on and HealthKit's
  fused distance and Milepost's GPS distance both land on the same workout;
  Health shows the sum.
- Background modes go in **`WKBackgroundModes`**, not `UIBackgroundModes` —
  watchOS has its own key. The wrong one builds, archives, exports and passes
  `builtin-validationUtility`; the App Store upload is the first thing that
  says no (`ERROR 90362: Invalid value 'workout-processing' for Info.plist key
  UIBackgroundModes`), after the build number has already been bumped.
  `location` is an **iOS** value and `WKBackgroundModes` rejects it too, with
  the same error and no value named. Background location on the watch needs no
  key at all: since watchOS 4 a workout session no longer grants it, and
  `allowsBackgroundLocationUpdates` is the whole mechanism.
  `smoke_test.sh` and `smoke_test_watch.sh` now fail on any of these. It needs `workout-processing`
  (or the session is suspended and the run stops) **and** `location` (what
  `allowsBackgroundLocationUpdates` requires, as on iOS).
- Finished activities reach the phone with `transferUserInfo`, not
  `sendMessage`: it is queued and survives the watch app being killed, so a run
  finished out of range still lands. The phone dedupes on `payload.id` because
  WatchConnectivity retries a transfer it never saw acknowledged.
- The payload carries `healthWorkoutID`. The watch already wrote the workout, so
  a non-nil value is what stops the phone writing a **second copy** of the same
  run into Health.
- Heart rate and calories are deliberately **not** stored on `Activity`. The
  watch wrote them to Health; the detail screen reads them back by date range.
  That is also what keeps them structurally unable to reach the friends backend
  (`WatchSyncTests.testAWatchActivityStillSharesStatsOnly`).
- The "Include route" switch is the phone's, and the watch honours it through
  `updateApplicationContext` — a setting has no history worth queueing, only a
  current value. A watch that has never heard from its phone defaults to **not**
  writing a route, matching the phone.
- Mirroring is a separate channel from WatchConnectivity:
  `startMirroringToCompanionDevice()` on the watch,
  `workoutSessionMirroringStartHandler` on the phone, and
  `sendToRemoteWorkoutSession(data:)` both ways. It works with either app in the
  background, which is why the phone can show a live run at all. The watch
  pushes a `MirroredWorkoutState` every 2s; the phone sends
  `WorkoutRemoteCommand`s. Both are wrapped in `WorkoutRemoteMessage` so an
  older build decodes nothing rather than misreading a message.
- While a mirrored session is live the Record tab hides its own controls. Two
  recorders on one run means two activities and two workouts in Health.
- The watch target compiles the app's `Sport`, `Units`, `RoutePoint`,
  `VoiceCue`, `RunRecorder`, `CalorieEstimator`, `SplitTimeline`,
  `Sport+HealthKit`, `Theme` and `SportIcon` — same reason the widget compiles
  its three: a watch app cannot link the iPhone app.
- A `ModelContainer` must be **held** for as long as its context is used.
  `let context = try makeContainer().mainContext` in a test helper reads as
  harmless and takes the whole test process down inside SwiftData, with no
  assertion failure — xcodebuild reports "Restarting after unexpected exit" and
  names the tests without saying why. Keep the container in a property.
- **Start must not wait on HealthKit.** `WatchWorkoutController.start` is
  synchronous: it starts the recorder, turns on GPS and sets `phase = .running`
  on the same run loop pass, then attaches the workout session on its own Task.
  The first version did it the other way round and froze on Start three ways —
  an unavailable Health database made the button do nothing at all,
  `beginCollection` blocked behind an unanswered permission sheet, and
  `startMirroringToCompanionDevice` hung with no phone in range — all while the
  sport list sat disabled waiting. A failed session costs heart rate, calories
  and the Health workout; it must never cost the run.
- For the same reason `end()` produces a payload whether or not a session ever
  attached. It used to `guard let session, let builder else { return nil }`,
  which silently threw away a whole GPS-recorded run.
- **`allowsBackgroundLocationUpdates = true` raises an uncatchable Obj-C
  exception** (`NSInternalInconsistencyException`, "Invalid parameter not
  satisfying: !stayUp || CLClientIsBackgroundable(...)") when the process is not
  backgroundable. Swift cannot catch it; the app dies. On watchOS a **running
  workout session** is what makes it backgroundable, so
  `WatchLocationService.allowBackgroundUpdates` is called only after
  `beginCollection` succeeds, gated on `isBackgroundEligible`.
- `MilepostWatchTests` (watchOS unit-test target) holds the journeys, driving
  the controller with an injected clock and **no Health database** — the case a
  real wrist hides until it bites. `run_tests.sh watch` runs them; `unit` and
  `all` include them, so `ship.sh` gates on them.
  Fixture traps, both of which silently measure nothing: a fix timestamped
  before `segmentStart` is dropped by the engine (inject the clock and advance
  it), and a pause with no clock movement is a zero-length interval that
  `closedPauses` drops on purpose.
- `-watch-preview` (DEBUG only, `WatchPreviewData`) fills the screens with a
  real twelve-minute run driven through the real recorder, so the watch UI can
  be looked at and captured at all; `-watch-preview-summary` and
  `-watch-preview-page-{splits,controls}` reach the other screens. Verified
  absent from the Release binary with `strings`.
- watchOS has no XCUITest, so `scripts/smoke_test_watch.sh` (build, install,
  cold launch in a watch simulator, then check the process is still alive) is
  the gate, and `ship.sh` runs it. `simctl io <watch sim> screenshot` returns a
  **stale framebuffer** — three shots across two relaunches came back
  byte-identical — so the process check is the signal, not the picture.
- **Building needs the watchOS platform installed** (`xcodebuild -downloadPlatform
  watchOS`, ~4 GB). Without it even the iOS scheme fails, because it embeds a
  watch app: "watchOS 26.5 must be installed in order to run the scheme".

## App Store submission (all in `scripts/`, run with `~/.venvs/spendcap/bin/python`)

- `asc_metadata.py` — the whole listing (categories, subtitle, description,
  keywords, URLs, copyright, age rating, review contact + notes, free price,
  availability in every territory). `--show` prints the live state. Contact
  fields come from the gitignored `asc-config.env`.
- Screenshots: `MILEPOST_SIM=<Pro Max UDID> TEST_RUNNER_MILEPOST_SHOTS=$PWD/build.nosync/screenshots-raw
  TEST_RUNNER_MILEPOST_LONG_RUN=1 ./scripts/run_tests.sh ui` writes the raw
  captures (the route test runs ~9 min so a split lands), then
  `asc_make_screenshots.py` composes the five panels and
  `asc_upload_screenshots.py --replace` uploads them to the 6.7" slot.
- `make_asc_header.py` — Header/Search Results banner into `marketing/asc-header/`
  (upload is browser-only).
- `asc_push_privacy_iris.py` — App Privacy = "Data Not Collected" through the
  private iris API; needs a fresh `fastlane spaceauth -u divinejdavis@gmail.com`
  cookie (2FA, so a person runs it; 401 = expired).
- `asc_submit_for_review.py --check` then without `--check` to submit
  (reviewSubmissions). Pricing and App Privacy are invisible to the pre-flight;
  read `meta.associatedErrors` on a 409.
- `attach_build.py --build N` after every ship, or the version keeps the old build.
- Privacy/support pages live in Personal-Website `milepost/{privacy,support}/`
  and deploy by scp to 159.203.110.79:/var/www/divinedavis/ (no auto-deploy).
