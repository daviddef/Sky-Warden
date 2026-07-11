# Sky Warden — Apple Watch modules

## What the watch surface should say

The watch is the smallest glance, so it carries exactly **one idea that no rival
does: how much the sources agree**. Every family leads with the temperature and
wraps it in the confidence ring — green when the models agree, amber the moment
they don't. That's the moat on a watch face.

| Family | Shows | Notes |
|---|---|---|
| `accessoryCircular` | Temp inside a **confidence gauge** | The hero. Ring fill = % agreement, colour = agree/disagree. |
| `accessoryCorner` | Temp + curved confidence gauge | Hugs a corner slot. |
| `accessoryRectangular` | Temp + condition + "agree / sources vary" + next tide | The full glance. |
| `accessoryInline` | `24° · sources vary` | The flag in the inline slot. |

Data flows one way and needs **no network on the watch**: the iOS app already
writes a snapshot to the App Group after every fetch
(`WeatherAggregator.publishToWatch` → `StoredWeatherData` in the shared defaults);
the widget reads it (`SkyWardenTimelineProvider.currentEntry`).

## Code, ready to wire

- **`WatchApp/SkyWardenWatchWidgets.swift`** — the modern **WidgetKit** modules
  (watchOS 9+), the four accessory families above. This is what the current watch
  face editor surfaces.
- **`WatchApp/ComplicationViews/SkyWardenComplications.swift`** — the legacy
  **ClockKit** set (watchOS 7–8), kept for older devices.
- Both compile against the shared `SkyWardenEntry` / `StoredWeatherData` /
  `UserDefaults.skyWardenShared` already defined in `Shared/SkyWardenShared.swift`.

The whole `WatchApp/**` folder is **excluded from the iOS target** (see
`project.yml`), so none of it affects the phone app or its build today.

## Why it isn't turned on yet

Adding an embedded watchOS target changes signing and the archive graph, and **a
mis-wired embedded target is the classic way to break the App Store archive** — the
exact risk this project has deferred before (widgets/watch). It also can't be
verified with the machine's screen locked. So the code exists; the target does not.
Turn it on deliberately, with the screen unlocked, following the steps below, and
archive once to confirm nothing broke.

## Wiring plan (do this at a keyboard, then archive to verify)

1. **App Group** (enables the phone→watch snapshot). Add the same App Group to the
   iOS app and the watch targets, e.g. `group.com.defranceski.skywarden`, and make
   sure `UserDefaults.skyWardenShared` uses it (it already references a group suite —
   confirm the identifier matches).

2. **Add the targets to `project.yml`.** Two new targets:

   ```yaml
     SkyWardenWatch:                 # the watchOS app
       type: application
       platform: watchOS
       deploymentTarget: "9.0"
       bundleId: com.defranceski.skywarden.watchkitapp
       sources:
         - path: SkyWarden-handover/SkyWarden-iOS/WatchApp
         - path: SkyWarden-handover/SkyWarden-iOS/Shared      # shared entry/defaults
       dependencies:
         - target: SkyWardenWatchWidgets
       entitlements:
         properties:
           com.apple.security.application-groups: [group.com.defranceski.skywarden]

     SkyWardenWatchWidgets:          # the WidgetKit complication extension
       type: app-extension
       platform: watchOS
       deploymentTarget: "9.0"
       bundleId: com.defranceski.skywarden.watchkitapp.widgets
       sources:
         - path: SkyWarden-handover/SkyWarden-iOS/WatchApp/SkyWardenWatchWidgets.swift
         - path: SkyWarden-handover/SkyWarden-iOS/Shared
       entitlements:
         properties:
           com.apple.security.application-groups: [group.com.defranceski.skywarden]
   ```

   Split the sources so `SkyWardenWatchWidgets.swift` lives in the extension and the
   ClockKit file (if you keep it) lives in the app; both need the shared model.

3. **Bundle-ID nesting matters.** The watch app must be
   `<iOS bundle>.watchkitapp` and the widget extension
   `<iOS bundle>.watchkitapp.widgets`, or the archive validator rejects it.

4. **Regenerate + archive.** `xcodegen`, then **archive the iOS scheme** (not just
   build) and run through Organizer validation *once* before shipping — that's the
   step that catches a broken embedded target.

5. **Provisioning.** First archive will mint the watch + extension provisioning
   profiles; make sure the App Group capability is on all three App IDs in the
   developer portal.

## Follow-ups once it's live
- A minimal watch **app** view (not just complications) mirroring the Simple Now
  screen — verdict word, temp, the confidence line, next-hours rain.
- Complication **deep-link** into that view.
- Drive refresh from the phone's background task so the snapshot stays fresh.
