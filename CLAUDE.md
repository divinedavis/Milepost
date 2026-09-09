# Milepost — working notes

A Strava-style tracker for runs, walks and bike rides: GPS record screen,
full-screen live recorder
(time / split pace / distance / splits), pause + resume, "No Movement
Detected" guard, save to a local SwiftData log, per-run detail with route map,
and a Dynamic Island / lock-screen Live Activity showing the mile in progress.
No backend, no account, no upload.

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
- Run / Walk / Ride, chosen from the chip on the Record tab, remembered in
  UserDefaults. The chip is only on screen before a run starts, so the sport
  cannot change mid-recording; `RecordScreen.sport` reads the recorder's own
  value while one is live in case the setting is changed elsewhere.
- The engine is identical for all three. What differs is the plausibility
  window and the wording. A 45-minute mile is a normal walk and outside the
  run bounds; 36 mph is a normal descent on a bike and outside them too. Get
  this wrong and the rate silently reads "-:--" for a whole activity.
- A ride reads in **speed** (mph / km/h), a run and a walk in **pace**
  (min/mi). `Sport.rateText` / `rateSuffix` / `rateLabel` are the only place
  that decides; do not call `Format.pace` directly in a view.
- `Sport` is compiled into the widget, so it cannot touch app-only types.
  That is why the spoken-duration helper lives on `Format` and
  `VoiceCuePhrase.spoken` is a thin alias to it.
- `Activity.sportRaw` was added after 1.0 shipped, with a default, so
  SwiftData migrates existing stored runs without a mapping model. Do not
  make it non-optional without a default.

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
- A crash mid-run would strand a card nobody owns, so the controller ends any
  stray activity on launch.
- Never `app.debugDescription` or an untyped `descendants(matching: .any)` on
  the Record tab — the MapKit accessibility tree takes minutes to walk.
- `RunRecorder` is the whole engine and is clock-injected; every rule
  (accuracy gate, stationary gate, split roll-over, paused time) has a unit
  test. Change a rule → change its test.
- Splits are stored in the unit the run was recorded with (`splitMeters`);
  the detail view labels them from that, not from the current setting.

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
