-- Separate allowance from receipt scans: at most 60 lookups per user per UTC day.
begin;
create table if not exists public.yueji_places_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  lookups integer not null check (lookups between 1 and 60),
  primary key (user_id, usage_day)
);
alter table public.yueji_places_usage enable row level security;
revoke all on public.yueji_places_usage from public, anon, authenticated;
create or replace function public.claim_places_request()
returns boolean language plpgsql security definer set search_path = '' as $$
declare account_id uuid := auth.uid(); used integer;
begin
  if account_id is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  insert into public.yueji_places_usage(user_id, usage_day, lookups)
    values(account_id, (now() at time zone 'UTC')::date, 1)
  on conflict (user_id, usage_day) do update set lookups = public.yueji_places_usage.lookups + 1
    where public.yueji_places_usage.lookups < 60
  returning lookups into used;
  return used is not null;
end;
$$;
revoke all on function public.claim_places_request() from public, anon;
grant execute on function public.claim_places_request() to authenticated;
notify pgrst, 'reload schema';
commit;
