# Sky Warden — Competitive Roadmap

_Synthesised from a teardown of 13 leading weather apps (Apple Weather, CARROT, Hello Weather,
Weather Underground, AccuWeather, Windy, Ventusky, Weawow, MyRadar, Flowx, Merry Sky / Tomorrow.io,
RadarScope, Yr.no) + user-sentiment and ensemble-forecasting research, 2026-07._

## The thesis

> **Mainstream-clean on the surface, pro-grade multi-source consensus underneath** — bracketing the
> exact gap between Apple Weather (loved for simple/no-ads, weak outside the US) and Windy (loved for
> pro data, too complex to answer "will it rain?").

The four category signals that matter:

1. **Accuracy is the #1 complaint (~28%).** Users already intuit single-source apps are worse. This
   is *exactly* Sky Warden's moat — lead with it.
2. **Monetisation resentment is #2 (~23% ads + ~19% paywall creep).** Every backlash came from ads or
   *removing* free features (AccuWeather, Ventusky, CARROT's subscription pivot, Weather Live's
   $9.99/week). Keep the core free + ad-free forever.
3. **The Dark Sky hole is still open.** Nobody fully replaced minute-by-minute precip + "rain in 15
   min" alerts. Most-requested experience in the category.
4. **Model-comparison is the loved enthusiast feature** (Windy, Ventusky, Flowx) — but always shown as
   raw spaghetti for pros. **Nobody translates disagreement into a plain-English confidence signal.**
   That translation gap is our wedge.

## The 12 highest-leverage bets

`[MOAT]` = only Sky Warden can credibly do this · `[STAKES]` = must-have to earn the daily open.
Status: ✅ done · 🟡 partial · ⬜ not started.

| # | Feature | Tag | Size | Status |
|---|---------|-----|------|--------|
| 1 | **Visible accuracy ledger** — "most accurate here lately", per-location, per-source | MOAT | M | ✅ MostAccurateCard on Detailed Now (learning/weighting states) → Sources (f22c981) |
| 2 | **Confidence signal on every forecast** — High/Med/Low from spread; widen range when unsure | MOAT | M | 🟡 confidence % on dial; Simple footer says "N agree · confident"; "soften headline when unsure" still to do |
| 3 | **Disagreement flags, only when material** — "4 of 9 say showers, 5 say dry" | MOAT | S | ✅ Simple footer: "Sources split on rain: 10–60% — worth a backup plan" (f377a70) |
| 4 | **Precip nowcast + rain-start/stop push** — the Dark Sky job | STAKES | M | ✅ Open-Meteo minutely_15 → "Rain starting in ~20 min" banner + provisional notification (fg + bg) (1a1eafb); 🟡 could add a full minute-by-minute strip |
| 5 | **Fast, un-paywalled radar with future frames** | STAKES | M | ✅ single mode + nowcast future frames + instant base map / "Sharpening" pill (8acc28d) |
| 6 | **Widgets + Apple Watch complication w/ confidence dot** | STAKES | M | ⬜ watch scaffolding exists; complications + widgets to build |
| 7 | **"Will it rain on my ___" activity planner** — decision framing | MOAT-adj | M | ⬜ (Plans tab is a stub to build on) |
| 8 | **Progressive-disclosure spaghetti/plume view** for power users | MOAT | M | ⬜ premium candy |
| 9 | **AQI + pollen as baseline (not premium)** | STAKES | S | ⬜ Open-Meteo air-quality API |
| 10 | **Marine/tides + aviation METAR** as the paid vertical | MOAT-adj | L | 🟡 tides exist; marine/METAR depth to add |
| 11 | **Restraint-first monetisation** — core free+ad-free; charge the enthusiast layer only | strategy | S | ⬜ |
| 12 | **Privacy stance** — no location-data selling, stated | strategy | S | ⬜ |

## Phased roadmap

### NOW — light up the moat cheaply + earn the daily open
- **#3 Disagreement flags in plain English** — near-free on data we already reconcile; instantly
  differentiating.
- **#1 Visible accuracy-ledger panel** — the ledger exists; surface it as *the* pitch ("we're
  weighting BOM — it's been ±1.2° here over 30 days").
- **#2 Confidence on the Simple headline** — kills false-precision distrust; pairs with #1.
- **#4 Precip nowcast + rain notifications** — the reason people open daily; without it the consensus
  story never gets seen.
- **#6 Widgets + Watch complication (confidence dot)** — carries the moat onto the glanceable surface.

### NEXT — round out the daily product + begin monetising where users tolerate it
- **#5 finish fast, un-paywalled radar** (single consolidated mode ✓ in progress).
- **#7 activity planner** — turns consensus into a decision; high shareability.
- **#9 AQI + pollen** — cheap, expected, closes the checklist gap vs Apple.
- **#11 + #12 restraint-first paywall + privacy** — stand up premium around the enthusiast layer.

### LATER — own the enthusiast / niche high ground
- **#8 spaghetti/plume power view** — flagship premium feature (study ModelSpread).
- **#10 marine + aviation METAR** — loyal, willing-to-pay niches; consensus matters most on go/no-go.
- **AI ensemble members in the ledger** — GraphCast / GenCast / ECMWF AIFS as scored inputs; real
  accuracy gain + "most sophisticated consensus engine" story.

## Notable references
- **ForecastAdvisor.com** — consumer forecast-verification (temp within 3°F, precip % correct,
  "Superior Forecaster" badge). A manual per-city version of our ledger — a validator to cite and
  echo in UI copy.
- **ModelSpread.com** — 82+ traces, member-agreement confidence score, 48h spaghetti → 7-day dots.
  The closest existing analog to our confidence layer; study before building #8.
- **ECMWF ~15–20% more skilful than GFS at days 3–5**; no model best everywhere → blending with bias
  correction is the correct thesis. AI ensembles (GenCast beats ECMWF ENS on many metrics) are the
  growth path.

_Correction from research: Merry Sky is Pirate-Weather-powered by default, not Tomorrow.io._
