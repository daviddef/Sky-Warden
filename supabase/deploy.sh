#!/usr/bin/env bash
#
# Sky Warden — one-shot Supabase proxy deploy.
#
# Prereqs (you do these once, they need YOUR login — I can't and shouldn't):
#   1. Create a project at https://supabase.com
#   2. brew install supabase/tap/supabase   (already done on this machine)
#   3. supabase login                        (opens a browser; authenticates you)
#
# Then, from the repo root:
#   bash supabase/deploy.sh <your-project-ref>
#
# The project ref is the code in your dashboard URL:
#   https://supabase.com/dashboard/project/<ref>
#
# The script reads the provider API keys from your (gitignored) Config.xcconfig,
# sets them as server-side secrets, pushes the cache table, deploys the function,
# and prints the two values to paste back into Config.xcconfig.

set -euo pipefail

REF="${1:-}"
if [[ -z "$REF" ]]; then
  echo "Usage: bash supabase/deploy.sh <project-ref>" >&2
  exit 1
fi

cd "$(dirname "$0")/.."          # repo root
CONFIG="Config.xcconfig"
if [[ ! -f "$CONFIG" ]]; then
  echo "❌ $CONFIG not found (it holds your provider keys, gitignored)." >&2
  exit 1
fi

# Pull a value out of Config.xcconfig ("KEY = value").
val() { grep -E "^$1[[:space:]]*=" "$CONFIG" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '[:space:]'; }

WT=$(val WORLDTIDES_API_KEY)
OW=$(val OPENWEATHER_API_KEY)
GN=$(val GNEWS_API_KEY)

# Reuse the app token if one is already set, else mint a long random one.
APP=$(val PROXY_APP_TOKEN)
if [[ -z "$APP" ]]; then APP=$(openssl rand -hex 24); fi

echo "▸ Linking project $REF …"
supabase link --project-ref "$REF"

# NOTE: `supabase db push` applies the migration but needs the DATABASE password
# (interactive), which a token-only login doesn't have. If you know it, run:
#     supabase db push
# Otherwise create the cache table once from the dashboard SQL editor by pasting
# supabase/migrations/0001_weather_cache.sql. The function works uncached until
# then. (This repo's initial deploy created the table via a one-shot function.)

echo "▸ Setting server-side secrets …"
SECRETS=(SKYWARDEN_APP_TOKEN="$APP")
[[ -n "$WT" ]] && SECRETS+=(WORLDTIDES_API_KEY="$WT")
[[ -n "$OW" ]] && SECRETS+=(OPENWEATHER_API_KEY="$OW")
[[ -n "$GN" ]] && SECRETS+=(GNEWS_API_KEY="$GN")
supabase secrets set "${SECRETS[@]}"

echo "▸ Deploying the function …"
supabase functions deploy weather --no-verify-jwt

BASE="https://$REF.supabase.co/functions/v1/weather"
echo
echo "✅ Deployed. Put these in $CONFIG and rebuild:"
echo
echo "   PROXY_BASE_URL   = $BASE"
echo "   PROXY_APP_TOKEN  = $APP"
echo
echo "Then verify (MISS first call, HIT within 15 min):"
echo "   curl -s \"$BASE?source=openmeteo&latitude=-27.87&longitude=153.35&hourly=temperature_2m\" \\"
echo "     -H \"x-skywarden-app: $APP\" -i | grep -i x-cache"
echo
echo "Once it works you can delete WORLDTIDES_API_KEY / OPENWEATHER_API_KEY from"
echo "$CONFIG — the app no longer needs them (they live only in Supabase now)."
