# Milepost — working notes

A Strava-style tracker for runs, walks and bike rides: GPS record screen,
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
- Sport raw values are `run`/`walk`/**`bike`** (not "ride"); the table's check
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
