-- Personal research allowance, separate from other AI features: at most 10 analyses per user per UTC day.
begin;
create table if not exists public.yueji_investment_research_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  analyses integer not null check (analyses between 1 and 10),
  primary key (user_id, usage_day)
);
alter table public.yueji_investment_research_usage enable row level security;
revoke all on public.yueji_investment_research_usage from public, anon, authenticated;
create or replace function public.claim_investment_research()
returns boolean language plpgsql security definer set search_path = '' as $$
declare account_id uuid := auth.uid(); used integer;
begin
  if account_id is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  insert into public.yueji_investment_research_usage(user_id, usage_day, analyses)
    values(account_id, (now() at time zone 'UTC')::date, 1)
  on conflict (user_id, usage_day) do update set analyses = public.yueji_investment_research_usage.analyses + 1
    where public.yueji_investment_research_usage.analyses < 10
  returning analyses into used;
  return used is not null;
end;
$$;
revoke all on function public.claim_investment_research() from public, anon;
grant execute on function public.claim_investment_research() to authenticated;
notify pgrst, 'reload schema';
commit;
