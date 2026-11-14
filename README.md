<h1 align="center"> Milepost </h1> <br>
<p align="center">
  <a href="https://apps.apple.com/us/app/milepost-run-walk-ride/id6808740421">
    <img alt="Milepost" title="Milepost" src="marketing/logo/runner-wordmark-dark.png" width="450">
  </a>
</p>

<p align="center">
  Track runs, walks and rides on iPhone and Apple Watch. Built with SwiftUI.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/milepost-run-walk-ride/id6808740421">
    <img alt="Download on the App Store" title="App Store" src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" width="140">
  </a>
</p>

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Feedback](#feedback)
- [Build Process](#build-process)
- [Logo](#logo)

## Introduction

A small, private tracker for runs, stroller runs, walks and bike rides on iPhone and Apple Watch. Pick your sport, start, watch time / pace / distance and per-mile splits live, pause when you hit a light, finish, save. Every activity keeps its route and shows up in the Block tab with a map and splits. Routes never leave the phone; with friends on (Sign in with Apple), only each activity's stats are shared with the people you accept, and their activities show up under Block > Friends.

Built with SwiftUI, MapKit, CoreLocation, SwiftData, ActivityKit and HealthKit, for iOS 17+ and watchOS 10+.

**Available for iPhone and Apple Watch.**

<p align="center">
  <img src="marketing/asc-screenshots-pinterest/01-brand.png" alt="Milepost" width="350">
</p>

## Features

A few of the things you can do with Milepost:

- Runs, stroller runs, walks and rides — a ride reads in mph, not minutes per mile
- The mile you are on in the Dynamic Island and on the lock screen
- Background tracking while the screen is off
- Miles or kilometers
- Spoken distance announcements every half, 1, 2 or 5 miles/kilometers; toggle and preview in You → Settings
- **Apple Watch app** that records on its own — heart rate and real calories from the
  workout session, distance and splits from the same engine the phone uses, and the
  finished activity queued to the iPhone even if it was out of range
- Start a run on the watch and the iPhone becomes a remote for it: live distance,
  pace and heart rate, with Pause and End
- **Apple Health**, off until you turn it on: each activity becomes a workout with
  its splits as laps and an estimated calorie burn, and heart rate your Watch
  recorded shows up on the activity. Your route is a second switch, off by default

<p align="center">
  <img src="marketing/asc-screenshots-pinterest/02-route-recording.png" alt="Recording a route" width="190">
  <img src="marketing/asc-screenshots-pinterest/03-route-detail.png" alt="Route detail" width="190">
  <img src="marketing/asc-screenshots-pinterest/04-route-save.png" alt="Saving an activity" width="190">
  <img src="marketing/asc-screenshots-pinterest/05-you-totals.png" alt="Your totals" width="190">
</p>

## Feedback

Feel free to [file an issue](https://github.com/divinedavis/Milepost/issues/new). Feature requests are always welcome. You can also reach us through the [support page](https://divinedavis.com/milepost/support/).

## Build Process

Building needs the watchOS platform installed (`xcodebuild -downloadPlatform watchOS`,
about 4 GB) — the iPhone scheme embeds the watch app, so without it even the iOS
build refuses to start.

```bash
./scripts/generate.sh        # project.yml -> Milepost.xcodeproj (xcodegen)
./scripts/run_tests.sh       # unit + UI (simulator)
./scripts/smoke_test.sh      # build, install, cold-launch in a simulator
./scripts/ship.sh            # tests, smoke, bump build, archive, TestFlight
```

Before releasing stroller running, apply `supabase/migrations/0004_stroller_running.sql`
to the friends backend so shared activities accept the new sport.

The recording engine is covered by unit tests and the main flows by XCUITests; `run_tests.sh` runs both.

## Logo

`scripts/make_wordmark.py` draws the runner wordmark and mark into `marketing/logo/`
(SVG + PNG, dark / light / navy); `scripts/make_icon.py` builds the app icon,
launch image and in-app wordmark from it.
