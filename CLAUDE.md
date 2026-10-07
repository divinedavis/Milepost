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
- **The two moving suites are flaky in a full run**, both in the same way: a
  save that works everywhere else does not show up in Block, and the test
  passes alone and passes when its own class is run in sequence.
  `MilepostRideUITests` did it on 2026-09-19 and
  `MilepostRouteUITests/testSavingWithAppleHealthOnKeepsTheActivityAndOffers\
Health` on 2026-09-20. Re-run the class before believing it; a real
  regression fails alone too.
- A row of labelled chips separated by `Spacer()` is **not** centred: each
  column is as wide as its own label, so the longest label (Stroller Run,
  wider than both the circle above it and "History") grows its column and
  shoves the middle one off the screen's centre line. The Record tab's
  controls and its three stats are equal thirds (`ControlColumn`,
  `maxWidth: .infinity`) for that reason, and
  `testStartStaysCentredForEverySport` pins it.

Launch splash (`LaunchSplashView.swift`, added 2026-09-20, modelled on Netflix's cold start):
- The static launch screen is the runner M (`LaunchLogo`, 144x120 pt) centred
  on `LaunchBackground`. The splash draws the same M at the same place and
  colour, holds, slides it left while I‑L‑E‑P‑O‑S‑T unfold beside it, holds,
  and cross-fades into the app. All vector, a straight port of
  `make_wordmark.py` (Arial Rounded MT Bold, 12° skew, the M as paths), so
  a wordmark change means changing both.
- **The clock counts rendered frames, not wall time.** The App body is
  evaluated a second before the launch screen fades, and mounting `RootView`
  (the map) stalls the main thread for most of a second: a wall clock had the
  whole thing over before it was seen, or lost the fade to the stall. Each
  frame adds at most `maxFrameStep`, so a stall pauses the show.
- `RootView` is mounted by `onReveal`, once the last letter has landed, so the
  stall hides inside the hold instead of swallowing the choreography. The
  `.task` that activates the watch session is on the `Group`, so it still runs
  at launch.
- The finished wordmark spans `widthFraction` (0.66) of the screen's width,
  toe to T, measured identical on a 17 Pro and a 17 Pro Max and at
  AccessibilityXXXL — nothing in it reads a font metric or a text style, and
  `Splash.font` is `.custom(_:fixedSize:)` with a `.system(size:)` fallback,
  so Dynamic Type cannot reach it. 0.86 was edge to edge and read as loud.
  Measure it by recording a launch and taking the widest dark frame's ink box.
- The M holds `holdLaunchPose` (0.55 s) before moving: the system's own
  cross-fade from the launch snapshot was still finishing at 0.4 s in the
  simulator and left a ghost M. Never timed on a phone.
- `-uitest` alone turns it off (every test would pay two seconds a launch);
  `MilepostSplashUITests` opts in with `-uitest-splash` and checks the
  hand-off. Cold launches only: the flags are `@State` set once per process.
- Checking it: `simctl io <sim> recordVideo` around a `simctl launch`, then
  `ffmpeg -vf fps=20` and a contact sheet. A single screenshot cannot judge it.

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

Auto-pause (`RunRecorder` "Auto-pause", You > Settings, added 2026-10-01, user request):
- **Off by default** (`AutoPauseSettings.enabledDefault`, pinned by
  `testAutoPauseIsOffByDefault` and the UI test). Read once at `start`; a
  change mid-run applies to the next one. Mirrored to the watch in the
  application context like the voice settings.
- Runs (and stroller runs) pause on a **walk**, walks and rides only when
  standing still: `autoPauseSpeeds(for:)`. Run: under 1.7 m/s (~15:47/mi)
  for 5 s pauses, 1.85 m/s (~14:30/mi) for 3 s resumes. The resume speed is
  kept low on purpose: set it above a slow jogger's pace and their run stays
  paused for good. Ground covered while auto-paused is not booked.
- Speed is CoreLocation's Doppler speed, or derived from the previous usable
  fix when it reports -1. Fixes past the 25 m accuracy gate decide nothing.
- **Fixes can stop arriving when standing still** (the simulator sends one
  and goes silent; phones can throttle). So the 0.5 s ticker also pauses
  when the slow stretch has lasted 5 s with no new fix, or no fix has shown
  movement for 10 s. It never pauses when the last fix was fast — a tunnel
  or a bridge on a run goes quiet while moving.
- Only an automatic pause resumes itself. `pause()` (the button, `finish()`)
  clears `isAutoPaused`, so a run cannot restart behind the save sheet.
- The watch's `phase` and `HKWorkoutSession` follow through
  `onAutoPauseChange`; phase is set **before** `session.pause()` so the
  session delegate does not mirror it back as a manual pause.
- Banner says "Auto-paused" (phone recorder + watch). The Live Activity
  shows the ordinary paused card.

Voice cues (`VoiceCue.swift`, `VoiceAnnouncer.swift`, `Resources/VoiceCues/`, recorded voice added 2026-09-16):
- The voice is ElevenLabs (Sarah, `eleven_flash_v2_5`), rendered ONCE by
  `scripts/make_voice_cues.py` into 236 short mp3 clips (1.4 MB) that ship
  in both the phone and watch bundles. The app never calls ElevenLabs: no key
  in the binary, no network needed mid-run, no per-mile cost.
- A cue is stitched: one whole distance phrase (`cue_dist_mi_3h` = "3 and a
  half miles complete.") then number/word clips for time and pace.
  `VoiceCueScript.clips(for:)` is the stitcher; `VoiceCueScript.library` is
  the full clip list; `VoiceCues.json` is the render script's copy of it and
  `testEveryClipInTheLibraryIsBundled` fails if the two drift or a clip is
  missing. Past 30 mi / 50 km (or an hour count over 59) it returns nil and
  the system voice (`AVSpeechSynthesizer`) says the same sentence.
- Adding a phrase: add it to BOTH `library()` in the script and
  `VoiceCueScript.library`, run the script (idempotent, renders only what is
  missing, hard-capped at 8,000 chars/run), run `generate.sh`, run tests.
  Changing the voice: change `VOICE_ID` and run with `--force` (~4.5k chars,
  ~2.2k credits on Flash). Key is keychain `nemo-elevenlabs`; the
  `lovili-elevenlabs` one is dead (401).
- Phrase text lives in `VoiceCuePhrase.distance` / `Format.spokenDuration`
  and the script's `distance_phrase`; keep them identical or the fallback
  says something different from the clips.
- The watch plays the same clips through the same class (`#if os(watchOS)`
  branch: no ducking options, `activate(options:)` instead of `setActive`).
  Its settings are the phone's, mirrored over `updateApplicationContext`
  into the watch's own UserDefaults by `WatchPhoneSync.apply`. Never heard
  on a real wrist; watchOS 11 routes to the speaker when no headphones are
  paired, older watchOS may show a route picker at the first cue.

Stats beyond distance and splits (added 2026-09-16, a runner asked for
"splits, fastest pace, elevation, distance"):
- **Fastest split** = best pace over a *completed* split
  (`[Split].fastestPace`). A partial split never counts or the opening
  sprint wins every run. Shown on the detail tiles, the live recorder, the
  watch summary, and as a bolt on the split row.
- **Elevation gain** = `SplitTimeline.elevationAscended` over the stored
  route (1 m hysteresis; fixes with no vertical accuracy are skipped), the
  same number Health is given. Read as ft with miles, m with km
  (`Format.elevation`). "--" means no altitude in the route (simulator
  routes from `simctl location` have none), which is not "0".

Past-route heatmap (`RouteHeatmap.swift`, Record tab, added 2026-09-24, user request):
- Every saved activity in the window is drawn on the Record map: covered once
  = light orange, darker each time another activity covers the same street
  (five shades, `RouteHeatmap.colors`, 1 / 2 / 3-4 / 5-9 / 10+ passes).
  Window defaults to **30 days**; the capsule under the wordmark switches
  7 / 30 / 90 days / All time / Off (`HeatmapWindow`, UserDefaults).
- "Same street" = a 15 m grid; each activity claims its cells plus their
  neighbours (GPS wanders 5-10 m between runs), counted once per activity so
  one loop of a track is not ten passes. A block over (60 m+) never counts.
  A stretch is as dark as its lighter end. No line across a >200 m gap.
- Routes are decoded on the main actor (SwiftData), the grid runs detached;
  recomputed only when the window or the activity id list changes.
- Friends (added 2026-09-24, user request): **blue** = streets a friend
  shared, **green** = a street you and a friend both covered (shaded by
  everyone's passes together), drawn blue < orange < green. Friends' data is
  `shared_streets` (migrations 0005/0006/0007): a SORTED SET of 15 m cells
  packed x<<32|y (no order = no direction), with every cell within a 400 m
  RADIUS of the activity's start, end, and any frequent endpoint (a start/end
  repeated across activities, `RouteHeatmap.frequentEndpoints`) dropped on
  the phone (`RouteHeatmap.streetCells`), and `start_date` cut to midnight
  UTC. Until 2026-10-07 it was 200 m trimmed ALONG the route, in route
  order, exact time: a loop back past home shared the front door (audit
  M1; 0007 cleaned the old rows). The map rebuilds lines from the set with
  `RouteHeatmap.chains`. **Opt-in, OFF by default** (`social.shareStreets`, You > "Share
  streets with friends") — the stats-only promise stands for everyone who
  never turns it on. Rows FK to `shared_activities` and cascade, so
  unsharing / stats-sharing off / account delete remove them. Server caps:
  10,000 cells a row, 1,000 rows an account; the app sends its 500 newest,
  tracked in `social.streetsUploaded.v2` so a session start doesn't
  re-upload (bump the suffix when the trim rule changes, so old rows are
  replaced).
  `friend_streets(since_ts)` (invoker, RLS decides, 300 rows) feeds the map.
  Friend lines go through cell centres and are Douglas-Peucker smoothed or
  they zig-zag. The demo backend's Jamie walk must be dense: corners >200 m
  apart are a gap and draw nothing.
- App Privacy now needs PRECISE_LOCATION (in `asc_push_privacy_iris.py`
  since 2026-09-24); pushing it needs a fresh `fastlane spaceauth`.
- Polylines are not in the accessibility tree, so `record.heatWindow`
  carries "N activities" as its value; `MilepostHeatmapUITests` seeds three
  walks with `-uitest-seed-heatmap` (DEBUG, `HeatmapPreviewData`).

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
- **Routes never leave the phone** — except opt-in street cells, see the
  heatmap section. `shared_activities` has sport, title,
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
- Sharing is **OFF for a new account** since 2026-10-07 (audit L1,
  `SocialStore.sharingDefault`; `createProfile` stores false). An account
  that already existed and has no stored choice is grandfathered ON at its
  first profile load (it was sharing under the old default; leaving it off
  would show "Nothing is shared" over rows still on the server). The switch
  lives in You > Friends only — no prompt on entry (owner rule). When on,
  `syncAll` upserts every local
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

Oura Ring (`OuraGuideView`, added 2026-09-23, user request):
- **There is no direct Oura link, by design.** The ring talks only to the Oura
  app, which trades with Apple Health: it WRITES heart rate (1-minute samples),
  active energy, steps, sleep; it READS workouts. So Oura support = the Health
  write + read that already existed, plus a guide (You > Apple Health > Use
  with Oura Ring) for the two Oura-side switches. The Oura Cloud API (OAuth,
  needs a server-held secret) was considered and not built.
- Oura imports a Health workout only on the **same day** and only while the
  Oura app is **open**. Nothing live reaches Milepost mid-run.
- The detail screen names who measured the heart rate (`HealthMetrics
  .heartRateSource`, an `HKSourceQuery` over the activity window), so a ring's
  sparse readings are not mistaken for a Watch's.
- Oura's own activity detection (10 min+) can log the same run a second time
  in Oura. Milepost cannot touch Oura's list; the guide says so.
- Never tried with a real ring.

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
- The sport picker is a **2x2 grid of square tiles**, not a list: as a list,
  Ride sat below the fold on every watch size. Tile side is bounded by the
  **visible height** as well as the width — at full column width two rows are a
  few points too tall and the bottom row clips. `aspectRatio(1, .fit)` cannot
  do this inside a `ScrollView`: a scroll view offers unbounded height, so it
  falls back to the content's natural size and the tiles come out half-width,
  silently. The `GeometryReader` goes **outside** the `ScrollView` for the same
  reason.
- Labels fall back to the mark alone when they will not fit on one line, via
  `ViewThatFits` with a 13pt / 11pt / icon-only ladder. `ViewThatFits` only
  works if the candidates are `.fixedSize`, or every one of them "fits". A
  mark-only tile needs an explicit `accessibilityLabel` or VoiceOver says
  "button". "Stroller Run" is the string that decides this: labelled at 46mm,
  mark-only at 42mm.
- **No permission sheet on app entry** (a standing rule across these apps).
  Location is requested on the tap that needs it, and the run waits for the
  answer via `pendingSport` rather than starting underneath the alert — an
  alert landing on a half-swapped screen is what made the first press of Start
  look broken. Health is requested inside `attachWorkoutSession`, which runs
  after recording has already begun, so nothing waits on it.
- **Never surface a raw HealthKit error.** `Missing
  com.apple.developer.healthkit entitlement` means nothing to someone wearing a
  watch; say what they lost (heart rate and calories) and what still works
  (distance, pace, splits).
- **Pause is on the metrics page as well as the controls page.** Pausing is the
  commonest thing you do mid-run and metrics is the page a run opens on; a
  control behind a swipe you have to know about is not usable with cold hands.
  End stays on controls only — ending by accident loses a run, pausing by
  accident costs a tap.
- `WatchRootView` is a `ZStack` with a cross-fade, not a bare `switch`. A bare
  switch swaps whole view *types* (a `NavigationStack`+`List` for a paged
  `TabView`), which SwiftUI tears down and rebuilds with no transition, and the
  first press of Start visibly snaps.
- Never call `requestWhenInUseAuthorization` on the tap that also changes the
  screen: the system alert lands on the half-swapped view. It only prompts once
  ever, so asking at launch is enough and a second call buys nothing.
- `-watch-preview` (DEBUG only, `WatchPreviewData`) fills the screens with a
  real twelve-minute run driven through the real recorder, so the watch UI can
  be looked at and captured at all; `-watch-preview-summary`,
  `-watch-preview-paused` and `-watch-preview-page-{splits,controls}` reach the
  other screens. The preview sets heart rate and calories, so it is also the
  worst case for vertical space on the metrics page — check a capture after any
  layout change there. Verified
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
- `make_creative_assets.py [OUT_DIR]` — the fall-2026 Asset Library set:
  header 3840x1646, search 3840x2560, universal 5244x2950 (RGB, no alpha)
  for the main page, plus a header per custom product page (`cpp-ride`,
  `cpp-watch`). Wordmark and tagline stay in the centre 60% x 70% (Apple
  crops edges); no prices, URLs, (c) or other platforms. Also writes a
  `preview-product-page.png` per header that is for eyes only, not upload.
- `asc_push_privacy_iris.py` — App Privacy = "Data Not Collected" through the
  private iris API; needs a fresh `fastlane spaceauth -u divinejdavis@gmail.com`
  cookie (2FA, so a person runs it; 401 = expired).
- `asc_submit_for_review.py --check` then without `--check` to submit
  (reviewSubmissions). Pricing and App Privacy are invisible to the pre-flight;
  read `meta.associatedErrors` on a 409.
- **A build with the watch app needs watch screenshots or the submission is
  refused** (`STATE_ERROR.SCREENSHOT_REQUIRED.APP_WATCH_SERIES_4`), which
  never came up while 1.0 carried build 17. `APP_WATCH_SERIES_4` is
  368x448, exactly the screen of the **Apple Watch SE 3 (44mm)** simulator;
  the 46mm and Ultra sims are the wrong size. Upload with
  `asc_upload_screenshots.py --display APP_WATCH_SERIES_4 --dir
  marketing/asc-watch-screenshots-navy`.
- **iMessage's App Store link preview shows the first WATCH screenshot**, not
  the iPhone one (seen 2026-09-24). The raw black watch capture looked broken
  there, so the uploaded set is composed: `make_watch_screenshots.py` puts the
  raw captures in `marketing/asc-watch-screenshots/` on the navy field with
  the wordmark and a headline, into `marketing/asc-watch-screenshots-navy/`.
  Upload that directory, never the raw one. Panel 1 is the preview.
  Since 2026-10-05 (user request) panel 1 is NOT a watch panel: it is the
  WHOLE first iPhone screenshot fitted to 448 tall on its own navy, so the
  share card looks like the listing's first screenshot (a top-half crop was
  rejected by the owner). Watch panels are 2-4. Recompose after
  any change to `asc-screenshots-navy/1.png`. App Review could object to an
  iPhone picture in the watch slot (2.3.3); if they do, this is why.
- Capturing them is awkward and `simctl io <watch sim> screenshot` is the
  stale-framebuffer trap, so record instead: start `recordVideo`, launch,
  wait, stop, and extract with `ffmpeg -vsync 0` (the file is variable rate,
  so `-vf fps=N` throws most of it away). The sim's screen sleeps about a
  second after the launch animation, so only screens that hold it awake come
  out: `-watch-preview` (metrics), `-watch-preview-page-controls`, and
  `-watch-preview-summary` all captured; the sport picker never did.
- Swapping the build on a version that is WAITING_FOR_REVIEW means cancelling
  the submission first (`PATCH /reviewSubmissions/{id} {"canceled": true}`),
  which drops it to DEVELOPER_REJECTED and **loses its place in the queue**.
  `attach_build.py` refuses in-review versions on purpose, so this is a
  deliberate two-step, not something to automate into the ship script.
- `attach_build.py --build N` after every ship, or the version keeps the old build.
- Privacy/support pages live in Personal-Website `milepost/{privacy,support}/`
  and deploy by scp to 104.236.120.144:/var/www/divinedavis/ (no auto-deploy).
