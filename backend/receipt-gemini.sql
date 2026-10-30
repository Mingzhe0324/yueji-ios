-- Run separately in the Supabase SQL editor before deploying receipt-gemini.
begin;
create table if not exists public.yueji_receipt_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  scans integer not null check (scans between 1 and 20),
  primary key (user_id, usage_day)
);
alter table public.yueji_receipt_usage enable row level security;
revoke all on public.yueji_receipt_usage from public, anon, authenticated;
create or replace function public.claim_receipt_scan()
returns boolean language plpgsql security definer set search_path = '' as $$
declare account_id uuid := auth.uid(); used integer;
begin
  if account_id is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  insert into public.yueji_receipt_usage(user_id, usage_day, scans)
    values(account_id, (now() at time zone 'UTC')::date, 1)
  on conflict (user_id, usage_day) do update set scans = public.yueji_receipt_usage.scans + 1
    where public.yueji_receipt_usage.scans < 20
  returning scans into used;
  return used is not null;
end;
$$;
revoke all on function public.claim_receipt_scan() from public, anon;
grant execute on function public.claim_receipt_scan() to authenticated;
notify pgrst, 'reload schema';
commit;
