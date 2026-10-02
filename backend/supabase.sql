-- Run once in the Supabase project's SQL Editor. No service-role key goes in the app.
create table if not exists public.yueji_backups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null check (octet_length(payload::text) <= 20000000),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);
alter table public.yueji_backups enable row level security;
revoke all on public.yueji_backups from anon;
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
  next_revision bigint;
begin
  if account_id is null then raise exception '请先登录。'; end if;
  if p_expected_revision < 0 or p_payload is null or jsonb_typeof(p_payload) <> 'object' or octet_length(p_payload::text) > 20000000 then
    raise exception '备份格式或大小无效。';
  end if;
  -- Serialize both the first insert and subsequent updates for this account.
  perform pg_advisory_xact_lock(hashtextextended(account_id::text, 0));
  select revision into previous_revision from public.yueji_backups where user_id = account_id for update;
  if previous_revision is null then
    if p_expected_revision <> 0 then raise exception '云端版本已改变，请重新检查备份。'; end if;
    insert into public.yueji_backups(user_id,payload,revision) values(account_id,p_payload,1);
    return 1;
  end if;
  if previous_revision <> p_expected_revision then
    raise exception '云端版本已改变。请检查或恢复最新备份，避免覆盖其他设备的记录。';
  end if;
  next_revision := previous_revision + 1;
  update public.yueji_backups set payload=p_payload, revision=next_revision, updated_at=now() where user_id=account_id;
  return next_revision;
end;
$$;
revoke all on function public.save_yueji_backup(jsonb,bigint) from public, anon;
grant execute on function public.save_yueji_backup(jsonb,bigint) to authenticated;
