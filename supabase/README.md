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

The whole thing is scripted. You only do the two steps that need *your* login:

```sh
# 1. Sign in (opens a browser — only you can do this)
supabase login

# 2. Deploy everything: link, push the schema, set secrets from Config.xcconfig,
#    deploy the function, and print the two values to paste back.
bash supabase/deploy.sh <your-project-ref>
```

Your project ref is the code in the dashboard URL:
`https://supabase.com/dashboard/project/<ref>`. It is not a secret. The script
reads the provider keys from your gitignored `Config.xcconfig` and sets them as
server-side secrets, so they never pass through anything but your own machine
and Supabase. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the
platform automatically.

<details><summary>What the script runs, if you'd rather do it by hand</summary>

```sh
supabase link --project-ref <ref>
supabase db push
supabase secrets set WORLDTIDES_API_KEY=… OPENWEATHER_API_KEY=… \
  GNEWS_API_KEY=… SKYWARDEN_APP_TOKEN=<long-random-string>
supabase functions deploy weather --no-verify-jwt
```
</details>

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
