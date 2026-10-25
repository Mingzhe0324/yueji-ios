-- Run in a disposable Supabase project after supabase.sql. All fixture changes roll back.
begin;
insert into auth.users(id) values ('a2c5d1e0-3261-4ee4-9a01-000000000001'), ('a2c5d1e0-3261-4ee4-9a01-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a2c5d1e0-3261-4ee4-9a01-000000000001', true);
do $$ begin
  if public.save_yueji_backup('{"version":6,"expenses":[]}'::jsonb, 0) <> 1 then raise exception 'First revision failed'; end if;
  begin
    perform public.save_yueji_backup('{"version":6,"expenses":[]}'::jsonb, 0);
    raise exception 'Stale revision was accepted';
  exception when serialization_failure then null; end;
end $$;
select set_config('request.jwt.claim.sub', 'a2c5d1e0-3261-4ee4-9a01-000000000002', true);
do $$ begin
  if exists(select 1 from public.yueji_backups) then raise exception 'Another account can read the ledger'; end if;
  begin
    insert into public.yueji_backups(user_id, payload) values ('a2c5d1e0-3261-4ee4-9a01-000000000001', '{"version":6}');
    raise exception 'Cross-account write was accepted';
  exception when insufficient_privilege then null; end;
  if public.save_yueji_backup('{"version":6,"expenses":[]}'::jsonb, 0) <> 1 then raise exception 'Independent account failed'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
  if public.yueji_sync_health() <> 1 then raise exception 'Health check failed'; end if;
  begin
    perform 1 from public.yueji_backups;
    raise exception 'Anonymous ledger read was accepted';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_yueji_backup('{"version":6}'::jsonb, 0);
    raise exception 'Anonymous ledger write was accepted';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
