<p align="center"><img src="marketing/logo/runner-wordmark-dark.png" alt="Milepost" width="520"></p>

# Milepost

A small, private tracker for runs, stroller runs, walks and bike rides on iPhone. Pick your
sport, start, watch time / pace / distance and per-mile splits live, pause
when you hit a light, finish, save. Every activity keeps its route and shows
up in the Block tab with a map and splits. Routes never leave the phone; with
friends on (Sign in with Apple), only each activity's stats are shared with the
people you accept, and their activities show up under Block > Friends.

- SwiftUI + MapKit + CoreLocation + SwiftData + ActivityKit, iOS 17+
- Runs, stroller runs, walks and rides — a ride reads in mph, not minutes per mile
- The mile you are on in the Dynamic Island and on the lock screen
- Background tracking while the screen is off
- Miles or kilometers
- Spoken distance announcements every half, 1, 2 or 5 miles/kilometers; toggle and preview in You → Settings
- Unit tests for the recording engine, XCUITests for the flows

## Logo

`scripts/make_wordmark.py` draws the runner wordmark and mark into `marketing/logo/`
(SVG + PNG, dark / light / orange); `scripts/make_icon.py` builds the app icon,
launch image and in-app wordmark from it.

## Develop

```bash
./scripts/generate.sh        # project.yml -> Milepost.xcodeproj (xcodegen)
./scripts/run_tests.sh       # unit + UI (simulator)
./scripts/smoke_test.sh      # build, install, cold-launch in a simulator
./scripts/ship.sh            # tests, smoke, bump build, archive, TestFlight
```

Before releasing stroller running, apply `supabase/migrations/0004_stroller_running.sql`
to the friends backend so shared activities accept the new sport.
