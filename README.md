# Sky Warden

> Product/display name: **Sky Warden** (two words). Internal identifiers stay
> single-word — bundle ID `com.defranceski.skywarden`, the `SkyWarden.xcodeproj`
> project, target/scheme `SkyWarden`, and Swift type names — since those can't
> contain spaces.

Multi-source iOS + watchOS weather app that reconciles four weather sources
(Open-Meteo, OpenWeatherMap, Apple WeatherKit, BOM) into a consensus reading and
visually flags where the sources disagree. See
[`SkyWarden-handover/HANDOVER.md`](SkyWarden-handover/HANDOVER.md) for the full
product design.

## Project layout

| Path | What it is |
|---|---|
| `project.yml` | XcodeGen spec — the source of truth for the Xcode project |
| `SkyWarden.xcodeproj` | **Generated** — do not edit by hand; regenerate instead |
| `Config.xcconfig` | API keys (gitignored). Copy from `Config.xcconfig.template` |
| `Support/iOS/` | Info.plist, entitlements, asset catalog for the iOS app |
| `SkyWarden-handover/SkyWarden-iOS/` | The Swift source (data layer + views) |

## First-time setup

```sh
brew install xcodegen           # if not already installed
cp Config.xcconfig.template Config.xcconfig   # then fill in your keys (optional)
xcodegen generate               # produces SkyWarden.xcodeproj
open SkyWarden.xcodeproj
```

Open-Meteo, BOM, and the moon/astro calculations need **no keys** — the app runs
and shows real consensus data out of the box. OpenWeather and WorldTides need
free/cheap keys in `Config.xcconfig`; without them those sources simply drop out.

### WeatherKit (native)

The app uses the native `import WeatherKit` framework (no JWT signing). To make
that source live you need a **paid Apple Developer account**: set your team in
the target's Signing & Capabilities and the WeatherKit + App Groups capabilities
are already declared in `Support/iOS/SkyWarden.entitlements`. Until then
WeatherKit fails gracefully like any other unavailable source.

## Build from the command line

```sh
xcodebuild build -project SkyWarden.xcodeproj -scheme SkyWarden \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

## What is wired vs. what's next

**Wired and verified building/running (this pass):**
- Buildable Xcode project (iOS app target), Info.plist, entitlements, config.
- Full data layer compiling: models, consensus/disagreement engine, all services.
- Native WeatherKit service + WeatherKit source added to the consensus set.
- Per-source 6s timeout + real failed-source tracking (drives the "unavailable" UI).
- App Group snapshot written after each fetch for the Watch complication to read.
- Background refresh (`BGAppRefreshTask`) actually runs against the last coordinate.

**Next steps (per HANDOVER.md build order):**
1. Rebuild the view layer to the current design (comfort dial, 9-tab structure,
   Scene tab) using `prototypes/skywarden-comfort-dial-and-scene.jsx` as the
   reference. The views currently in the project are the earlier 5-tab iteration —
   they compile and run but are placeholders for the redesign.
2. Add the watchOS app target: it needs a SwiftUI `@main` entry point (not yet
   present) and ClockKit complication registration. The phone→Watch data contract
   (`StoredWeatherData` in `Shared/SkyWardenShared.swift`) is already in place.
3. Crowd-source "People's Weather" backend.
