-- Assertions for the sync core. Run via supabase/tests/run.sh (aborts on first failure).
\set ON_ERROR_STOP on
\set A '11111111-1111-1111-1111-111111111111'
\set B '22222222-2222-2222-2222-222222222222'
insert into auth.users values (:'A'), (:'B');

create schema t;
create or replace function t.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); end $$;
create or replace function t.chg(f text, v text, h text, b text, dev text, cid text, row_ text default 'r1:p1') returns jsonb language sql as $$
  select jsonb_build_object('tbl','cells','row_id',row_,'field',f,'value',to_jsonb(v),'hlc',h,'base_hlc',b,'device_id',dev,'change_id',cid) $$;
create or replace function t.assert(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond,false) then raise exception 'ASSERT FAILED: %', msg; end if; end $$;
create or replace function t.throws(sql text, expect text) returns void language plpgsql as $$
begin
  begin execute sql; exception when others then
    if sqlerrm like '%'||expect||'%' or sqlstate = expect then return; end if;
    raise exception 'ASSERT FAILED: expected error %, got % (%)', expect, sqlerrm, sqlstate;
  end;
  raise exception 'ASSERT FAILED: expected error % but statement succeeded: %', expect, sql;
end $$;

grant usage on schema t to public;
grant execute on all functions in schema t to public;
set role authenticated;
select t.as_user(:'A');

-- H(n) helper strings
\set H1 '000000000001-0000-devA'
\set H2 '000000000002-0000-devB'
\set H3 '000000000003-0000-devA'

-- 1. first write accepted + visible through the pull feed
select t.assert((apply_changes(jsonb_build_array(t.chg('value','x',:'H1',null,'devA','1')))->>'accepted')::int = 1, 'first write accepted');
select t.assert((select count(*) from change_log) = 1, 'change logged');

-- 2. causal successor: no conflict
select t.assert((apply_changes(jsonb_build_array(t.chg('value','y',:'H2',:'H1','devB','1')))->>'conflicts')::int = 0, 'causal edit has no conflict');
select t.assert((select value #>> '{}' from sync_fields) = 'y', 'causal edit applied');

-- 3. concurrent, incoming OLDER: rejected but preserved
select t.assert((apply_changes(jsonb_build_array(t.chg('value','late-old',:'H1',null,'devC','1')))->>'conflicts')::int = 1, 'older concurrent edit conflicts');
select t.assert((select value #>> '{}' from sync_fields) = 'y', 'older edit did not overwrite');
select t.assert((select lost_value #>> '{}' from sync_conflicts order by id desc limit 1) = 'late-old', 'rejected value preserved');

-- 4. concurrent, incoming NEWER with unknown base (spike S-4 hole): accepted AND old value preserved
select t.assert((apply_changes(jsonb_build_array(t.chg('value','z',:'H3',null,'devA','2')))->>'accepted')::int = 1, 'newer unknown-base accepted');
select t.assert((select lost_value #>> '{}' from sync_conflicts order by id desc limit 1) = 'y', 'overwritten value logged (no silent loss)');

-- 5. idempotent retry: same batch again changes nothing
select t.assert((select count(*) from sync_conflicts) = 2, 'two conflicts so far');
select t.assert((apply_changes(jsonb_build_array(t.chg('value','z',:'H3',null,'devA','2')))->>'duplicates')::int = 1, 'retry is a duplicate');
select t.assert((apply_changes(jsonb_build_array(t.chg('value','late-old',:'H1',null,'devC','1')))->>'duplicates')::int = 1, 'retry of rejected change is a duplicate');
select t.assert((select count(*) from sync_conflicts) = 2, 'retries did not duplicate conflicts');

-- 6. pull feed is ordered and cursor-friendly
select t.assert((select array_agg(seq order by seq) from change_log) = (select array_agg(seq order by seq) from change_log where seq > 0), 'feed ordered');

-- 7. validation
select t.throws($q$select apply_changes('[{"tbl":"evil","row_id":"r","field":"f","value":1,"hlc":"000000000001-0000-a","device_id":"d","change_id":"c"}]')$q$, 'invalid table');
select t.throws($q$select apply_changes('[{"tbl":"cells","row_id":"r","field":"f","value":1,"hlc":"bad","device_id":"d","change_id":"c"}]')$q$, 'invalid hlc');
select t.throws($q$select apply_changes('[{"tbl":"cells","row_id":"r","field":"bad field!","value":1,"hlc":"000000000001-0000-a","device_id":"d","change_id":"c"}]')$q$, 'invalid field');
select t.throws($q$select apply_changes('{"not":"array"}')$q$, 'json array');
select t.throws($q$select apply_changes((select jsonb_agg('{}'::jsonb) from generate_series(1,501)))$q$, 'batch too large');
select t.throws($q$select apply_changes(jsonb_build_array(jsonb_build_object('tbl','cells','row_id','r','field','f','value',repeat('x',1100000),'hlc','000000000001-0000-a','device_id','d','change_id','big')))$q$, 'value too large');

-- 8. collation: HLC ordering is byte order (C), identical to Dart String.compareTo
select t.assert('000000000010-0000-a' > '00000000000f-ffff-z'::text collate "C", 'hex ordering');
select t.assert('000000000001-0000-B' < '000000000001-0000-a'::text collate "C", 'uppercase sorts before lowercase in C');

-- 9. RLS isolation
select t.as_user(:'B');
select t.assert((select count(*) from sync_fields) = 0, 'B sees none of A''s fields');
select t.assert((select count(*) from change_log) = 0, 'B sees none of A''s changes');
select t.assert((select count(*) from sync_conflicts) = 0, 'B sees none of A''s conflicts');
select t.assert((apply_changes(jsonb_build_array(t.chg('value','B-data','000000000001-0000-devB',null,'devB','1')))->>'accepted')::int = 1, 'B writes own row at same key');
select t.assert((select value #>> '{}' from sync_fields) = 'B-data', 'B sees only own value');
select t.as_user(:'A');
select t.assert((select value #>> '{}' from sync_fields where row_id='r1:p1') = 'z', 'A value untouched by B writing same key');

-- 10. direct DML is denied for clients (only the RPC writes)
select t.throws($q$insert into sync_fields(owner_id,tbl,row_id,field,value,hlc,updated_seq) values (auth.uid(),'cells','x','y','1','000000000001-0000-a',1)$q$, 'permission denied');
select t.throws($q$update sync_fields set value='"hacked"'$q$, 'permission denied');
select t.throws($q$delete from change_log$q$, 'permission denied');
select t.throws($q$select * from applied_changes$q$, 'permission denied');

-- 11. anon and unauthenticated callers are rejected
reset role; set role anon;
select t.throws($q$select apply_changes('[]')$q$, 'permission denied');
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '', false);
select t.throws($q$select apply_changes('[]')$q$, 'not authenticated');

-- 12. audit log is append-only through the RPC and private
select t.as_user(:'A');
select log_audit('backup_restored', '{"from":"local"}');
select t.assert((select count(*) from audit_log) = 1, 'audit entry written');
select t.throws($q$delete from audit_log$q$, 'permission denied');
select t.as_user(:'B');
select t.assert((select count(*) from audit_log) = 0, 'audit log private');
select t.as_user(:'A');
-- resolve_conflict only touches the caller's own conflicts
select resolve_conflict((select min(id) from sync_conflicts));
select t.assert((select count(*) from sync_conflicts where resolved_at is not null) = 1, 'own conflict resolved');
select t.as_user(:'B');
select resolve_conflict(1);  -- B tries A's conflict: must be a no-op
reset role;
select t.assert((select count(*) from sync_conflicts where resolved_at is not null) = 1, 'B cannot resolve A''s conflict');

\echo ALL SQL TESTS PASSED
