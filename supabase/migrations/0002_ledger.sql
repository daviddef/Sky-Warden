-- Sky Warden — the pooled skill ledger.
--
-- The accuracy moat scores each source against the local thermometer and keeps a
-- per-source mean-absolute-error on a ~55 km grid. On-device that scoreboard is
-- private and starts empty for every new user. This table pools it: each device
-- contributes the DELTA of its observation-scored errors, the server sums them,
-- and any device on the same grid reads the fleet's combined scoreboard. A new
-- user near a well-measured spot inherits proven weights immediately.
--
-- What is stored is only how wrong each source has been on a grid cell — a count
-- and a summed error. No user, no device id, no coordinate finer than ~55 km, no
-- timestamp trail. It is aggregate accuracy, not location history.

create table if not exists public.ledger (
  grid          text        not null,          -- "lat,lon" snapped to 0.5°, ≈55 km
  source        text        not null,          -- WeatherSource.rawValue
  metric        text        not null,          -- SkillMetric.rawValue (temp | wind)
  count         bigint      not null default 0,
  sum_abs_error double precision not null default 0,
  updated_at    timestamptz not null default now(),
  primary key (grid, source, metric)
);

alter table public.ledger enable row level security;   -- no policies: only the
                                                        -- Edge Function (service role) touches it.

-- Add a batch of deltas atomically. Summing on conflict is what makes SkillStat's
-- monoid hold server-side: the row ends up exactly as if one device had made every
-- observation. security definer so the function's service role can write under RLS.
create or replace function public.ledger_add(p_grid text, p_entries jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  e jsonb;
begin
  for e in select * from jsonb_array_elements(p_entries)
  loop
    insert into public.ledger (grid, source, metric, count, sum_abs_error)
    values (
      p_grid,
      e->>'source',
      e->>'metric',
      (e->>'count')::bigint,
      (e->>'sumAbsError')::double precision
    )
    on conflict (grid, source, metric) do update
      set count         = ledger.count + excluded.count,
          sum_abs_error = ledger.sum_abs_error + excluded.sum_abs_error,
          updated_at    = now();
  end loop;
end;
$$;
