-- Run the complete script in your Supabase SQL Editor. No privileged key belongs in the app.
begin;
create table if not exists public.yueji_backups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 20000000),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);
alter table public.yueji_backups enable row level security;
revoke all on public.yueji_backups from public, anon;
grant select, insert, update on public.yueji_backups to authenticated;
drop policy if exists yueji_select_own on public.yueji_backups;
drop policy if exists yueji_insert_own on public.yueji_backups;
drop policy if exists yueji_update_own on public.yueji_backups;
create policy yueji_select_own on public.yueji_backups for select to authenticated using ((select auth.uid()) = user_id);
create policy yueji_insert_own on public.yueji_backups for insert to authenticated with check ((select auth.uid()) = user_id);
create policy yueji_update_own on public.yueji_backups for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.save_yueji_backup(p_payload jsonb, p_expected_revision bigint)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  account_id uuid := auth.uid();
  previous_revision bigint;
begin
  if account_id is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if p_expected_revision is null or p_expected_revision < 0 or p_payload is null
     or jsonb_typeof(p_payload) <> 'object' or octet_length(p_payload::text) > 20000000
     or p_payload->>'version' is distinct from '6' then
    raise exception 'Invalid ledger payload' using errcode = '22023';
  end if;
  -- Serialize first inserts as well as updates. Each account has an independent lock.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account_id::text, 0));
  select revision into previous_revision from public.yueji_backups where user_id = account_id for update;
  if previous_revision is null then
    if p_expected_revision <> 0 then raise exception 'Cloud revision changed' using errcode = '40001'; end if;
    insert into public.yueji_backups(user_id, payload, revision) values(account_id, p_payload, 1);
    return 1;
  end if;
  if previous_revision <> p_expected_revision then
    raise exception 'Cloud revision changed' using errcode = '40001';
  end if;
  update public.yueji_backups set payload = p_payload, revision = previous_revision + 1,
    updated_at = now() where user_id = account_id;
  return previous_revision + 1;
end;
$$;
revoke all on function public.save_yueji_backup(jsonb, bigint) from public, anon;
grant execute on function public.save_yueji_backup(jsonb, bigint) to authenticated;

-- A configuration check that reveals no accounts, balances or ledger contents.
-- Created last in the transaction so a successful check means installation completed.
create or replace function public.yueji_sync_health()
returns integer language sql stable security invoker set search_path = '' as $$ select 1; $$;
revoke all on function public.yueji_sync_health() from public;
grant execute on function public.yueji_sync_health() to anon, authenticated;
notify pgrst, 'reload schema';
commit;
