-- Separate allowance from receipt scans: at most 100 analyses per user per UTC day.
begin;
create table if not exists public.yueji_bank_analysis_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  analyses integer not null check (analyses between 1 and 100),
  primary key (user_id, usage_day)
);
alter table public.yueji_bank_analysis_usage enable row level security;
revoke all on public.yueji_bank_analysis_usage from public, anon, authenticated;
create or replace function public.claim_bank_analysis()
returns boolean language plpgsql security definer set search_path = '' as $$
declare account_id uuid := auth.uid(); used integer;
begin
  if account_id is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  insert into public.yueji_bank_analysis_usage(user_id, usage_day, analyses)
    values(account_id, (now() at time zone 'UTC')::date, 1)
  on conflict (user_id, usage_day) do update set analyses = public.yueji_bank_analysis_usage.analyses + 1
    where public.yueji_bank_analysis_usage.analyses < 100
  returning analyses into used;
  return used is not null;
end;
$$;
revoke all on function public.claim_bank_analysis() from public, anon;
grant execute on function public.claim_bank_analysis() to authenticated;
notify pgrst, 'reload schema';
commit;
