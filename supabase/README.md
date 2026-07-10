# Sky Warden — central data proxy (Supabase)

Holds the weather API keys **server-side** and caches responses per location-grid
so users don't share/drain one quota. Apple WeatherKit stays native on-device and
is **not** proxied. The client falls back to direct provider calls when
`PROXY_BASE_URL` is unset, so the app runs before this is deployed.

```
device ─► WeatherKit (native, on-device)
device ─► /functions/v1/weather?source=… ─► Open-Meteo · OpenWeather · WorldTides · GNews
             (keys here, cached per grid+TTL)
```

## One-time setup

```sh
# 1. Install the CLI and sign in
brew install supabase/tap/supabase
supabase login

# 2. Create a project at https://supabase.com (free tier), then link it
supabase link --project-ref <your-project-ref>

# 3. Apply the schema (creates the cache table)
supabase db push          # or paste supabase/migrations/0001_weather_cache.sql in the SQL editor

# 4. Set the server-side secrets (these leave the app binary entirely)
supabase secrets set \
  WORLDTIDES_API_KEY=<your-worldtides-key> \
  OPENWEATHER_API_KEY=<your-openweather-key> \
  GNEWS_API_KEY=<optional-gnews-key> \
  SKYWARDEN_APP_TOKEN=<make-a-long-random-string>
# SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

# 5. Deploy the function (public endpoint, guarded by our app token)
supabase functions deploy weather --no-verify-jwt
```

## Point the app at it

The deploy prints a URL like `https://<ref>.supabase.co/functions/v1/weather`.
Put it (and the same app token) in `Config.xcconfig`:

```
PROXY_BASE_URL   = https://<ref>.supabase.co/functions/v1/weather
PROXY_APP_TOKEN  = <the same long random string>
```

Then rebuild. Once this is set, the app routes Open-Meteo / OpenWeather /
WorldTides / GNews through the proxy — **remove those provider keys from
`Config.xcconfig`**, since the client no longer needs them.

## Verify

```sh
curl -s "https://<ref>.supabase.co/functions/v1/weather?source=worldtides&lat=-27.87&lon=153.35&heights&extremes&days=2&datum=LAT" \
  -H "x-skywarden-app: <token>" -i | grep -i x-cache   # MISS first call, HIT within 6h
```

## Notes & next steps
- **Abuse hardening:** the app token is a deterrent, not a wall (it still ships in
  the binary, rotatable). For production, gate with **App Attest / DeviceCheck**.
- **Licensing:** Open-Meteo's free tier is non-commercial — move to their
  commercial plan (keys still live only here) before a paid launch.
- **Reuse:** this same project is where the accuracy-backtesting ledger and
  People's Weather votes will live (next roadmap phases) — one backend.
