-- Sky Warden — shared response cache for the weather proxy.
-- One row per (source · location-grid · significant-params); the Edge Function
-- reads/writes it with the service role. RLS is ON with no policies, so the
-- public anon key cannot read the cache directly — only the function can.

create table if not exists public.cache (
  key         text primary key,
  payload     jsonb        not null,
  expires_at  timestamptz  not null,
  updated_at  timestamptz  not null default now()
);

create index if not exists cache_expires_idx on public.cache (expires_at);

alter table public.cache enable row level security;

-- Optional housekeeping: purge expired rows. Run via pg_cron if enabled, e.g.
--   select cron.schedule('purge-weather-cache', '*/30 * * * *',
--     $$delete from public.cache where expires_at < now()$$);
