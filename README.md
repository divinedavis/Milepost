# Milepost

A small, private run tracker for iPhone. Start a run, watch time / pace /
distance and per-mile splits live, pause when you hit a light, finish, save.
Every run keeps its route and shows up in Activities with a map and splits.
Nothing leaves the phone.

- SwiftUI + MapKit + CoreLocation + SwiftData, iOS 17+
- Background tracking while the screen is off
- Miles or kilometers
- Unit tests for the recording engine, XCUITests for the flows

## Develop

```bash
./scripts/generate.sh        # project.yml -> Milepost.xcodeproj (xcodegen)
./scripts/run_tests.sh       # unit + UI (simulator)
./scripts/smoke_test.sh      # build, install, cold-launch in a simulator
./scripts/ship.sh            # tests, smoke, bump build, archive, TestFlight
```
