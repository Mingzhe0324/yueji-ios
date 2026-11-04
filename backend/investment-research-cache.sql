-- Optional 24-hour per-account report cache; no service-role key required.
begin;
create table if not exists public.yueji_investment_report_cache (
 user_id uuid not null references auth.users(id) on delete cascade,
 cache_key text not null check (cache_key ~ '^[a-f0-9]{64}$'),
 report jsonb not null,
 created_at timestamptz not null default now(),
 primary key(user_id,cache_key)
);
alter table public.yueji_investment_report_cache enable row level security;
revoke all on public.yueji_investment_report_cache from public, anon, authenticated;
create or replace function public.read_investment_report(report_key text)
returns jsonb language sql security definer set search_path = '' as $$
 select report from public.yueji_investment_report_cache
 where user_id = auth.uid() and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 and cache_key = report_key and created_at > now() - interval '24 hours';
$$;
create or replace function public.save_investment_report(report_key text, report_value jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare account_id uuid := auth.uid();
begin
 if account_id is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  raise exception 'Sign in required' using errcode='42501';
 end if;
 if report_key !~ '^[a-f0-9]{64}$' or report_value is null or octet_length(report_value::text) > 250000 then
  raise exception 'Invalid report';
 end if;
 -- Serialize writes for this account so the storage bound survives concurrent calls.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account_id::text,0));
 delete from public.yueji_investment_report_cache where user_id=account_id and created_at < now()-interval '24 hours';
 insert into public.yueji_investment_report_cache(user_id,cache_key,report)
 values(account_id,report_key,report_value)
 on conflict(user_id,cache_key) do update set report=excluded.report,created_at=now();
 delete from public.yueji_investment_report_cache where user_id=account_id and cache_key in
 (select cache_key from public.yueji_investment_report_cache where user_id=account_id order by created_at desc,cache_key offset 20);
end;
$$;
revoke all on function public.read_investment_report(text) from public,anon;
revoke all on function public.save_investment_report(text,jsonb) from public,anon;
grant execute on function public.read_investment_report(text) to authenticated;
grant execute on function public.save_investment_report(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
