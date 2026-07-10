# SkyWarden — Handover to Claude Code

## What this is

SkyWarden is a multi-source weather app for iOS + watchOS. It fetches from four
independent weather sources in parallel (Open-Meteo, OpenWeatherMap, Apple
WeatherKit, BOM), merges them into a consensus reading, and — critically —
visually flags whenever the sources disagree instead of pretending false
precision. On top of that sits a "comfort dial": a five-ring semicircular
gauge that maps temperature, rain, wind, UV and humidity onto a human comfort
scale rather than raw units, so a glance answers "is it actually nice outside"
not just "what's the temperature."

There are two things in this handover:

1. **`SkyWarden-iOS/`** — a partial native Swift/SwiftUI project. The data
   layer (models, services, disagreement/consensus engine) is solid and
   should be built on directly. The view layer is an **earlier iteration**
   and needs a rebuild pass — see "What needs rebuilding" below.
2. **`prototypes/skywarden-comfort-dial-and-scene.jsx`** — a React reference
   prototype (built for Claude's artifact preview, not for shipping) that
   reflects the **current, agreed-upon design**: the tab structure, the
   comfort dial with its labelling fix, the illustrated Scene tab, and all
   the layout-bug fixes worked through with the user. **Treat this JSX file
   as the visual and interaction source of truth** for what the SwiftUI
   views should look like and do. It is not meant to run as-is in Swift —
   it's the design reference to translate faithfully into SwiftUI.

---

## App identity

- **Name:** SkyWarden
- **Bundle ID:** `com.defranceski.skywarden`
- **Tagline:** "Weather, from more than one sky."
- Naming history: the app started as SkyWarden, was briefly renamed to
  "Clearcast" mid-project after an App Store name-availability check flagged
  SkyWarden as close to an existing app called "SkyRadar," then reverted
  back to SkyWarden as the final decision. If you spot any stray "Clearcast"
  references anywhere they're leftover from that middle phase — treat
  SkyWarden as correct and Clearcast as the one to clean up.
- Other names considered and rejected along the way: SkyWeather (taken),
  Skyve (taken, dating app).

---

## The five data sources

| Source | Auth | Notes |
|---|---|---|
| Open-Meteo | none | Free, best hourly resolution, also has a free historical archive API back to 1940 (ERA5) |
| OpenWeatherMap | API key | Free tier 1,000 calls/day |
| Apple WeatherKit | Apple Dev account | Use the **native `import WeatherKit` Swift framework**, not the REST API — simpler, no manual JWT signing needed. Enable via Xcode → Signing & Capabilities → WeatherKit |
| BOM (Bureau of Meteorology) | none | Unofficial JSON feed reverse-engineered by the community; nearest station lookup by lat/lon; note BOM serves over plain HTTP not HTTPS, needs an ATS exception in Info.plist |
| WorldTides | API key | ~$3/month for 1,000 requests, used only for tide height/curve, not weather |

Existing Swift services for all of these are in `SkyWarden-iOS/Services/`.
`WeatherAggregator.swift` fans out the fetch with `TaskGroup`, each source has
a 6-second timeout, and if a source fails the aggregator degrades gracefully
rather than failing the whole screen.

---

## The consensus + disagreement engine

`Engine/ConsensusCalculator.swift` and `Engine/DisagreementEngine.swift`.

- Consensus temperature/rain/wind/humidity/UV = **trimmed mean** across
  however many sources responded (drops the single highest and lowest
  reading if 3+ sources are available, otherwise plain mean).
- Each field has a disagreement threshold (temp ±2°, rain ±15%, wind ±10,
  UV ±1, humidity ±10). Spread beyond 1x the threshold = minor disagreement
  (⚠️), beyond 2x = major (🚨).
- An overall confidence score (0–100%) is computed by penalising each
  flagged field, weighted by how much that field matters (temp/rain weighted
  highest at 0.3 each, wind 0.2, UV/humidity 0.1 each).

This logic is fully implemented in Swift already and should not need
significant changes — just wiring into the new view layer.

---

## The comfort model (the core design idea)

This is the single most important design concept in the app and is **not
yet in the Swift views** — it needs building from scratch in SwiftUI,
following `prototypes/skywarden-comfort-dial-and-scene.jsx` as the reference.

Each of 5 measurements (temperature, rain, wind, UV, humidity) is mapped to
a **comfort score from −1.0 to +1.0**:

- **+1.0** → needle points left (9 o'clock) → very comfortable
- **0.0** → needle points straight up (12 o'clock) → borderline
- **−1.0** → needle points right (3 o'clock) → uncomfortable

The scoring curves (not linear — both "too cold" and "too hot" score
negative for temperature, for example) are fully worked out in the JSX
prototype's `RINGS` array — port these functions directly, they're
calibrated against real research (Brisbane thermal comfort studies, Lawson
wind-comfort criteria, Cancer Council Australia UV guidelines, SE Queensland
humidity norms).

### The dial itself

- Five concentric **semicircular** arcs (not full circles — the whole point
  is the left/right comfortable/uncomfortable split, a full circle loses
  this instantly).
- Icon badges sit **directly on each ring's own track**, at the top/base of
  that ring (12 o'clock position) — a small dark circle behind the emoji so
  it reads clearly against any ring colour. This was a deliberate fix after
  an earlier iteration used floating spoke-labels that all clustered
  together unreadably at one corner (see screenshots discussion in this
  conversation — genuinely worth looking at why that failed before
  rebuilding).
- Two small tick marks per ring show **today's forecast min and max** at
  their scored positions on the arc, with a faint bracket between them.
- A dashed bracket in amber/red shows the **disagreement span** between
  furthest-apart source readings on that ring, when applicable.
- Small coloured dots (one per source) show where each individual source's
  reading would place the needle — only shown when a "sources" toggle is on.
- Tapping a ring shows its value + comfort label + min/max range in the
  centre readout; tapping again returns to the default "Comfort: Good/OK/
  Rough" overall summary.
- **Critical layout lesson learned:** the centre readout text and the ring
  box must be laid out as **separate, normal-flow blocks** (stacked in a
  flex column), not one absolutely positioned on top of the other with
  manually-guessed offsets. Every overlap bug hit during this build came
  from trying to calculate absolute pixel offsets for the readout text
  instead of just giving it a real, fixed-height block in document flow.
  Build the SwiftUI version with a `VStack` containing the ring `ZStack`
  followed by a fixed-height `VStack` for the readout — don't use
  `.overlay()` with manual offsets for this.

### Overall rating banner

Sits above the dial. Generates a short, warm, specific sentence — not a
score — based on season, location, overall comfort score, and which ring is
worst. E.g. "A perfect winter's day in Brisbane — comfortable and clear." or
"Heatwave conditions — 38°. Avoid outdoor exertion between 10am and 5pm."
Logic is in the JSX prototype's `ratingText()` function — port the branching
logic and phrase bank, expand the phrase variety in Swift since users will
see this daily.

### Pills row

Below the dial, a 3-column grid of tappable pills — one per ring — showing
icon + value + a "⚠️ varies" flag if that measurement has source
disagreement. These duplicate/mirror the ring taps as a bigger, easier
touch target, since the rings themselves are fairly small on a phone
screen. Went through several size iterations in this conversation before
landing on the current sizing in the JSX — use those exact proportions
(padding, font sizes) as the starting point rather than re-deriving from
scratch.

---

## Tab structure

Nine tabs, bottom tab bar, each owning exactly one concept — **do not let
content bleed between tabs or stack multiple concerns onto one screen**.
This was a real problem earlier in the design process (everything crammed
onto one scrolling "Now" screen) and the fix was strict separation:

1. **Now** — rating banner, comfort dial, pills, confidence strip, "on this
   day" historical mini-comparison, hourly scroll strip. Nothing else.
2. **Scene** — the illustrated alternate view (see below). New addition,
   not yet in most of the conversation history — it's the most recent
   feature discussed.
3. **Today** — full hourly breakdown, list format.
4. **Week** — full 7-day forecast, list format, disagreement badges per day.
5. **Tides** — tide curve with a real time-of-day X-axis (12am/6am/12pm/6pm
   labels + a "NOW" marker line), high/low event cards, moon phase.
6. **Plans** — reads Apple Calendar via EventKit, flags outdoor events
   (keyword matching: sport names, "bbq", "beach", "hike", etc.) against the
   forecast, shows impact level (🚨 major / ⚠️ watch / 🌦 minor / ✅ clear)
   and a plain-English warning per event.
7. **UV** — UV guardian: WHO-scale colour dial, sun-protection time window,
   Slip/Slop/Slap/Seek/Slide action row, toggleable "children & babies"
   guidance panel (Cancer Council AU wording), seasonal monthly UV chart
   for context ("winter in QLD is still UV 6-7, unlike southern states").
8. **Sky** — astronomical events: eclipses, meteor showers, planetary
   oppositions. Rare events (rarity: "rare") get push notifications
   scheduled 3 days and 1 day before. Data source for production: NASA JPL
   Horizons API + IAU meteor shower calendar; hardcoded near-term events are
   fine as a placeholder.
9. **News** — 2 most recent local weather stories, official BOM warnings
   badged distinctly (⚠ Official, red accent) and sorted to the top. Free
   sources: BOM Warnings Summary RSS (per state), BOM Anonymous FTP (same
   warnings as machine-readable XML), BOM Space Weather API (geomagnetic/
   aurora, needs free registration). GNews API as a general-news fallback
   (100 free calls/day) if BOM's own feed isn't enough for general weather
   news, not just official warnings.
10. **Sources** — full transparency tab: confidence bar, per-ring source
    breakdown (each source's raw reading + diff from consensus, expandable),
    and the crowd-sourced "People's Weather" widget (see below).

---

## The Scene tab (newest feature — build this fresh, nothing in Swift yet)

An illustrated alternate view of current conditions — a beach house scene
where every visual element is driven by a real number, nothing decorative:

- **Sky colour** blends continuously through the day using keyframe
  interpolation (11 keyframes: midnight → dawn → morning → midday → golden
  hour → sunset → dusk → night), each with a 3-stop gradient (top/mid/
  bottom) so sunrise/sunset get a real colour transition through the sky,
  not a flat two-colour blend.
- **Water line** rises and falls with actual tide height, sine-eased between
  the two nearest tide events so the motion isn't linear/robotic.
- **Clouds** — count and opacity scale with rain probability; built as
  multi-lobed soft shapes with a drop-shadow lobe underneath for volume,
  not flat overlapping ellipses.
- **Rain** — only appears above 25% chance, gets denser and wind-slanted
  above 55%.
- **The house** — proper beach-house architecture: raised on stilts, pitched
  roof with ridge highlight/shadow, chimney, porch with support posts,
  mullioned windows that glow warm amber at dusk/night, a door with its own
  small window, steps down to the sand, deck railing with individual
  balusters.
- **Palm tree** — leans and fronds sway further when wind speed is high.
- **Foreground dune grass** — bends more sharply with wind.
- **Seagulls** — small silhouettes appear only on calm, clear, non-rainy
  daylight scenes, purely for a touch of life.
- **Stars** fade in as the sky darkens (tied to a `stars` value per sky
  keyframe), invisible during daylight.
- A glassy overlay pill top-left shows current time + day phase, top-right
  shows tide height + rising/falling/turning status.
- Below the illustration, a small legend grid explains what each visual
  element maps to, in plain language.

**Full working SVG source for this is in the JSX prototype's `SceneTab`
function** (and its helper constants `SKY_KEYFRAMES`, `STARS`, `skyAt()`,
`hexLerp()`, `lerpNum()`) — this is genuinely the fastest path to a correct
SwiftUI/`Canvas` or SwiftUI/`Shape`-based port. Translate the SVG path/shape
logic into SwiftUI `Path` and `Canvas` drawing calls; the maths (gradient
interpolation, sine easing for tide, keyframe blending) ports directly.

**Build note:** SwiftUI's `Canvas` API (iOS 15+) is almost certainly the
right tool here rather than composing dozens of `Shape` views — it's
built for exactly this kind of custom immediate-mode illustration and will
perform much better than 40+ individual SwiftUI views re-rendering every
frame as the tide/sky/rain values change.

---

## Crowd source — "People's Weather"

Anonymous, daily emoji voting ("How does it actually feel outside right
now?" 😎/🙂/😐/😬/🥵) shown on the Sources tab. Prototype uses the browser
artifact's shared key-value storage; **production should use a small
backend table**:

```sql
CREATE TABLE crowd_votes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_key TEXT NOT NULL,      -- lat/lon grid bucket, e.g. "hope-island"
  vote_date    DATE NOT NULL,      -- local date
  vote         TEXT NOT NULL,      -- great/good/ok/bad/awful
  submitted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE VIEW crowd_daily_summary AS
SELECT location_key, vote_date, vote, COUNT(*) as count
FROM crowd_votes GROUP BY location_key, vote_date, vote;
```

Dedup one-vote-per-day via `identifierForVendor` (IDFV), hashed, not stored
raw — no account or personal data needed. Any small hosted Postgres
(Supabase, etc.) works fine for this; there's no need for anything
elaborate.

---

## Watch complication

Two-ring circular complication:
- **Outer ring** = temperature, colour-coded cold(blue)→mild(green)→
  warm(orange)→hot(red)
- **Inner ring** = rain probability, white when dry, deepening to blue with
  probability
- Centre text: temp + rain% on two lines
- Amber pulse ring around the needle position when any source disagreement
  exists that day

Existing Swift scaffold: `WatchApp/ComplicationViews/SkyWardenComplications.swift`
using `CLKComplicationDataSource`. Data shared from the phone app via an
App Group (`group.com.defranceski.skywarden`) in `UserDefaults`, key
`latestWeather`, JSON-encoded `StoredWeatherData` struct. This part is
already scaffolded and should just need wiring to real data once the main
app is fetching properly.

---

## Historical data ("On This Day")

`https://archive-api.open-meteo.com/v1/archive` — free, no key, ERA5
reanalysis back to 1940. For "this day N years ago," call with
`start_date`/`end_date` both set to the same calendar date in the prior
year(s), same lat/lon as the current forecast location. Also used for the
30-year WMO climate-normal baseline (1991–2020) shown as a comparison
reference. Shown compactly on the Now tab (today / 1yr / 5yr / 30yr-avg,
4-column strip) — this is a good "always visible, no tap required" pattern,
don't bury it behind a disclosure.

---

## BOM Radar (researched, not yet built)

Nearest station to the reference location (Hope Island, QLD) is **Mt
Stapylton, IDR663** (128km range). Free PNG frames via anonymous FTP
(`ftp.bom.gov.au/anon/gen/radar/`, personal use only, not for commercial
redistribution) update every 6–10 minutes. **Recommended production
approach: RainViewer API** (`api.rainviewer.com`) — documented, reliable,
includes BOM data in a global mosaic tile layer, has a free tier. This
hasn't been prototyped visually yet — worth a dedicated Radar tab or a
card on the Tides tab once built.

---

## Design tokens

All colour/type decisions should stay consistent with what's in the JSX
prototype's `T` object and font choices (SF Pro Display throughout, no
custom font needed). Key colours:

```
navy    #0B1929   deepest background
surface #132D4A   elevated surface
card    #1A3A5C   card background
good    #3DD68C   comfortable / confidence high
caution #F5A623   borderline / minor disagreement
bad     #E05555   uncomfortable / major disagreement
rain    #5BA3D4
tide    #4ECDC4
moon    #D4C47A
wind    #A78BFA
astro   #C084FC

Source identity: Open-Meteo #5BA3D4 · OpenWeather #F5A623 ·
                 WeatherKit #3DD68C · BOM #C084FC
```

---

## Suggested build order for Claude Code

1. **Get the existing Swift data layer compiling** — `Models/`, `Engine/`,
   `Services/`, `Shared/` should mostly just need a fresh Xcode project
   wrapper, Info.plist permissions (location, calendar, BOM's HTTP
   exception), and `Config.xcconfig` filled in with real API keys.
2. **Rebuild the view layer from scratch** following the JSX prototype as
   the design reference, tab by tab, starting with **Now** (the comfort
   dial is the hardest part — get that right first, using `Canvas` or
   careful `Path`/`ZStack` composition, and structure the centre-readout
   layout as normal document flow per the note above).
3. **Scene tab** next — this is genuinely new work, port the SVG logic to
   SwiftUI `Canvas`.
4. Remaining tabs (Today, Week, Tides, Plans, UV, Sky, News, Sources) are
   comparatively simple list/card layouts — lower risk, can go in any order.
5. Watch complication once the phone app has real data flowing.
6. Crowd source backend + wiring last — needs a small hosted database,
   everything else in the app works fully without it.

---

*Prepared for Claude Code handover. All Swift files under `SkyWarden-iOS/`
went through a brief mid-project rename to "Clearcast" and back to
SkyWarden — internal type names have been renamed accordingly, but double-
check for any stray "Clearcast" references if something doesn't compile.*
