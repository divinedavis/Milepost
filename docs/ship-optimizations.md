# Ship optimisations — all 150 ideas, tracked

Started 2026-10-23. Two lists: Claude's 50 (C1–C50) and the owner's ~100 from
another model (O, by section). Status:

- **DONE** — built, in the scripts/app now (with the commit that did it)
- **HAD** — already true before this work
- **NEXT** — applicable, not built yet (phase noted)
- **DUP** — same as another item (points to it)
- **N/A** — does not apply here, or is wrong (reason)
- **NO** — declined by the owner

Baseline (build 38, 2026-10-23): ship ~51 min; 20 min of it running tests,
the rest builds (~15 separate `xcodebuild test` runs), archive, upload.
Per-step timings now go to `~/Library/Logs/milepost-ship-timings.csv`.

## Claude's 50

| # | Idea | Status |
|---|---|---|
| C1 | build-for-testing once, test-without-building for every pass | DONE (run_tests.sh `build_once`) |
| C2 | -xctestrun per pass | DUP C1 (scheme + derivedDataPath does the same) |
| C3 | One shared DerivedData across runs | DONE (`Milepost-tests` DerivedData) |
| C4 | Skip generate.sh when nothing changed | DONE (`xcodegen --use-cache`) |
| C5 | Swift Testing / audit / smoke reuse the suite's results | DONE (unit xcresult read; audit once; smoke uses built app) |
| C6 | Build the watch app once | NEXT (phase 2: watch tests still build their scheme) |
| C7 | Xcode compilation caching | NEXT (phase 2, measure) |
| C8 | Skip package plugin/macro validation, pin packages | NEXT (phase 2) |
| C9 | Debug builds one architecture | HAD (ONLY_ACTIVE_ARCH = YES) |
| C10 | No dSYM in Debug | HAD (dwarf) |
| C11 | Tests picked by changed files | NEXT (phase 3) |
| C12 | Full suite before review, affected tests otherwise | NO — owner keeps the full suite every ship |
| C13 | Logic tests as unit tests | HAD (RunRecorder, RouteHeatmap, SplitTimeline are unit-tested) |
| C14 | Merge single-check UI tests | NEXT (phase 3) |
| C15 | Deep-link launch flags instead of tapping | HAD (-open-tab, seed flags) |
| C16 | Condition waits instead of fixed sleeps | NEXT (phase 3; recovery test 22 s → 5 s DONE) |
| C17 | Shorter waitForExistence timeouts | NEXT (phase 3) |
| C18 | Injected clock for the route tests | NEXT (phase 3, larger) |
| C19 | Autosave interval as a launch flag | DONE (`-uitest-autosave-interval`) |
| C20 | Audit only changed screens | NEXT (phase 3) |
| C21 | Parallel simulator clones | NO for now — conflicts with the one-simulator rule (16 GB Mac); owner to decide |
| C22 | One booted simulator for the whole ship | NEXT (phase 2: smoke still shuts it down) |
| C23 | Pre-warmed simulator snapshot | NEXT (phase 2) |
| C24 | Pin the simulator by UDID by default | NEXT (phase 1b) |
| C25 | Disable Siri/Spotlight in the test sim | NEXT (phase 2) |
| C26 | Relaunch instead of reinstall | HAD (XCUIApplication relaunches) |
| C27 | Location once per pass | HAD (still/moving/riding per pass) |
| C28 | Retry a failed test once, log flakes | DONE (`-retry-tests-on-failure`, ~/Library/Logs/milepost-flaky-tests.log) |
| C29 | Resume a failed ship | DONE (commit that passed skips to archive) |
| C30 | Cache passing results by commit | DUP C29 |
| C31 | Archive reuses the test build cache | N/A — Release vs Debug builds share nothing; archive DerivedData is already incremental |
| C32 | Archive + export warm | HAD |
| C33 | Upload with an API key | HAD (altool --apiKey) |
| C34 | Background upload | N/A — upload is ~1 s for 9 MB |
| C35 | Background attach after processing | DONE (testflight_notes.py polls; attach only on submit) |
| C36 | Skip watch smoke when no watch change | NEXT (phase 2) |
| C37 | Machine-wide build lock | DONE (wait_for_quiet_mac.sh at ship start) |
| C38 | Queue runner across apps | NEXT (needs Marracat/FAC scripts; their sessions own them) |
| C39 | Fixed nightly slots per app | NEXT (same) |
| C40 | Refuse to start on low memory/disk | NEXT (phase 1b) |
| C41 | Pre-commit compile check | NEXT (phase 4) |
| C42 | Fastest gates first | NEXT (phase 1b) |
| C43 | Stop on first failure | HAD (set -e) |
| C44 | Strict concurrency only in CI | N/A — no CI |
| C45 | Static checks: duplicate sims, ui_all entries, stale project | NEXT (phase 1b) |
| C46 | Per-step timing history | DONE (ship-timings.csv) |
| C47 | Slowest tests report | NEXT (phase 1b) |
| C48 | Flaky test list | DONE (flaky log) |
| C49 | One-line ship summary | NEXT (phase 1b) |
| C50 | Weekly cache cleanup incl. archives | NEXT (check the existing job) |

## Owner's list — Xcode build & Swift compilation

| Idea | Status |
|---|---|
| Single-file compilation in Debug | HAD (incremental is Xcode's Debug default) |
| No dSYM in Debug | HAD |
| Shared files as a local Swift package | NEXT (phase 5) |
| Conditional XcodeGen | DONE (C4) |
| ONLY_ACTIVE_ARCH Debug | HAD |
| EAGER_LINKING = YES | DONE (project.yml) |
| Profile slow type checks | NEXT (phase 4) |
| Explicit types in big ViewBuilders | NEXT (after the phase 4 report) |
| DEAD_CODE_STRIPPING = NO Debug | N/A — negligible |
| LLVM_LTO = NO Debug | HAD (default) |
| xcfilelist for run scripts | N/A — no run-script build phases |
| -parallelizeTargets | HAD (scheme default) |
| Max concurrent compile tasks | HAD (defaults to all cores) |
| Supabase as a binary XCFramework | N/A — compiled once, cached incrementally |
| No index store in scripts | DONE (COMPILER_INDEX_STORE_ENABLE=NO) |
| Pin packages | DUP C8 |
| Cache SwiftPM checkouts | HAD (local Mac keeps them) |
| Non-Debug scripts only at archive | HAD (MetricKit check is a grep in ship.sh) |
| No signing until packaging | HAD (CODE_SIGNING_ALLOWED=NO) |
| Asset catalog optimisation = time | NEXT (phase 2, measure) |
| Vector assets | N/A — icons are generated once; little to gain |
| Remove unused imports | NEXT (phase 4) |
| No @_exported import | HAD (none) |
| Batch mode in Release | HAD (default) |
| DerivedData on a RAM disk | N/A — 16 GB Mac, memory is the scarce resource |
| Pre-generated voice cues/holidays | HAD (rendered once, bundled) |
| Modular watch models | DUP phase 5 package |
| Module verifier off Debug | HAD (default off) |
| Pre-computed typography | N/A — no measured cost |
| Preview assets via DEVELOPMENT_ASSET_PATHS | N/A — no preview assets |
| -Onone Debug | HAD |
| Shallow clones | N/A — no CI |
| Quiet build output | HAD (scripts log to files) |
| Pre-warm runtimes in CI images | N/A — no CI (C23 is the local version) |
| Widget without app services | HAD (widget compiles 3 small files) |

## Owner's list — XCUITest & testing

| Idea | Status |
|---|---|
| Demo login flags | HAD (-uitest-social-demo) |
| Splash off in tests | HAD |
| No animations in tests | DONE (UIView.setAnimationsEnabled(false) under -uitest) |
| Predicates instead of sleeps | DUP C16 |
| Pre-grant permissions | DONE (simctl privacy grant location-always; Health cannot be granted) |
| Typed queries, not descendants(.any) | NEXT (phase 3 sweep) |
| Scope queries to containers | NEXT (phase 3) |
| Seed data by flags | HAD |
| Parallel workers | DUP C21 |
| In-memory SwiftData | HAD |
| Logic in unit tests | DUP C13 |
| Faster GPS playback | N/A — 10× a run's speed fails the run's plausibility check; C18 instead |
| Static location for still tests | HAD |
| Wipe UserDefaults in-app | HAD |
| No attachments on pass | HAD (Xcode default: deleted on success) |
| Screen recording only on failure | HAD (passing results are < 1 MB) |
| One launch per journey | DUP C14 |
| Separate building from testing | DUP C1 |
| Shard across machines | N/A — one Mac |
| Pre-boot simulator | HAD (boot()) |
| Hardware keyboard off | NEXT (phase 2) |
| Health via demo flags | HAD |
| Audit static screens only | DUP C20 |
| In-memory network mocks | HAD (DemoSocialBackend) |
| Crash reporter popups | N/A — not a real simulator setting |
| Injected clock for watch tests | HAD |
| "Indigo logging" | N/A — not a documented setting |
| Unique identifiers | HAD (check_test_coverage.py enforces) |
| Don't test Apple's UI | N/A — the Live Activity card is ours; the test is deliberate |
| Minimal unit test target | HAD |
| MetricKit off in tests | NEXT (phase 1b) |
| No device UI tests in CI | N/A — no CI |
| Moving-route tests nightly only | NO — owner, 2026-10-23: every ship |
| Autosave file by flag | HAD |
| Sanitizers off | HAD |

## Owner's list — deployment & App Store

| Idea | Status |
|---|---|
| API-key auth | HAD |
| Reuse the JWT | NEXT (phase 4) |
| Async dSYM upload | N/A — no crash service |
| ARCHS arm64 archives | HAD (archives are device-only) |
| Skip Bitcode | N/A — Bitcode is gone |
| altool/notarytool concurrency | N/A — notarytool is for Mac apps; upload is ~1 s |
| Validate before upload | N/A — upload validates; the smoke test catches plist errors first |
| Strip symbols in Release | HAD (Release default) |
| Compress voice clips | N/A — 1.8 MB |
| Build number from env | N/A — project.yml bump is how XcodeGen projects carry it |
| TestFlight automatic, review gated | HAD (owner rule 2026-10-23) |
| Skip metadata on binary-only builds | HAD (metadata is a separate script) |
| Batch ASC requests | N/A — a few calls a day |
| Profiles via API | HAD (-allowProvisioningUpdates + API key) |
| Prune profiles | NEXT (phase 4 check) |
| Export straight to output | HAD |
| Holiday events by cron | HAD (launchd 06:20) |
| Reuse the archive | HAD |
| Clean DerivedData selectively | HAD (cleanup job) |
| Lint changed files only | N/A — no SwiftLint |
| Fail fast on signing | NEXT (phase 1b) |
| Watch embedded once | HAD |
| What to Test from commits | DONE (testflight_notes.py, build-N tags) |
| Parallel CI stages | N/A — no CI |
| Cache dependencies | DUP |
| Screenshots on one device | HAD |
| ITSAppUsesNonExemptEncryption = NO | HAD |
| Exclude docs from bundles | HAD (resources are listed explicitly) |
| Organizer report async | NEXT (phase 1b: run in background) |
| Headless CI | N/A — no CI |
| Code coverage off when unused (found while doing this) | DONE (-enableCodeCoverage NO) |
