# Raw marketing captures

Source: `MilepostUITests/MilepostRouteUITests.swift`,
`testMovingRunSavesAndAppearsInActivities`, run on iPhone 17 Pro Max
simulator (UDID 075B6525-9503-47FD-BAE6-F1BD2483CD56) with
`TEST_RUNNER_MILEPOST_SHOTS=<dir>` and `TEST_RUNNER_MILEPOST_LONG_RUN=1`.
All PNGs are 1320x2868 (verified with `sips`).

- `map-route.png` — the record tab collapsed back to the map card mid-run,
  showing the route line drawn in over Prospect Park after ~1.2 mi covered.
- `route-recording.png` — the full-screen live recorder: time, split pace,
  distance and the splits bar, expanded back out after the map check.
- `route-save.png` — the save sheet right after tapping Finish, with the
  auto-filled run title field (bonus capture, not one of the five named in
  the brief but written by the same test pass).
- `route-detail.png` — the saved run's detail screen: route map, Distance,
  and the "Splits (mi)" list showing the completed first split.
- `you-totals.png` — the You tab's totals ("This week" / all-time) with the
  just-saved run counted in.
- `activities-list.png` — the Activities tab showing the saved run as a row
  before it's opened.

## Notes / deviations

- The simulated GPS route was played back at 5 m/s (vs. the script's normal
  3.5 m/s jog) so the ~9-minute long-run capture would fit under this
  environment's per-command time budget. This does not touch app or test
  logic, only the `simctl location start --speed` playback parameter passed
  outside the test; it makes the displayed pace read faster than a normal
  jog (~5:22/mi instead of ~7:40/mi).
- One test-source fix was required to get past the Dynamic Island assertion
  and reach the later screens: `MilepostUITests/MilepostRouteUITests.swift`
  hardcoded `label BEGINSWITH "Mile 1"` when checking the expanded Live
  Activity, but `TEST_RUNNER_MILEPOST_LONG_RUN=1` deliberately drives the
  run past the 1.0 mi split boundary (to have a real split for
  `route-detail.png`), at which point `RunRecorder.swift` bumps
  `splitIndex` to 2 ("Mile 2"). The literal "Mile 1" match would always fail
  on this path regardless of GPS speed. Changed the predicate to
  `BEGINSWITH "Mile "` (matches any mile number) — same regression coverage
  (asserts the expanded island shows mile-in-progress text), no longer
  hardcoded to a number the long-run branch is designed to exceed. Not
  committed/pushed per instructions; flagging for review.
