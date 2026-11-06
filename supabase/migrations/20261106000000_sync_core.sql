-- Folio sync core.
-- Server contract (mirrored by packages/sync_engine `resolve` + `FakeServer`):
--   * sync_fields : current value + HLC of every syncable field (tbl,row_id,field), per owner
--   * change_log  : ordered feed of ACCEPTED changes, pulled by clients with `seq > cursor`
--   * sync_conflicts : every value that lost a concurrent edit (never silently dropped)
--   * apply_changes(jsonb): the ONLY write path. Idempotent per (device_id, change_id).
-- HLC strings are fixed-width (see Hlc.toString) so plain text comparison == logical order;
-- they MUST use COLLATE "C" so ordering matches the Dart client byte-for-byte.

create table public.sync_fields (
  owner_id   uuid   not null references auth.users(id) on delete cascade,
  tbl        text   not null,
  row_id     text   not null,
  field      text   not null,
  value      jsonb,
  hlc        text   collate "C" not null,
  updated_seq bigint not null,
  primary key (owner_id, tbl, row_id, field)
);

create table public.change_log (
  seq        bigserial primary key,
  owner_id   uuid   not null references auth.users(id) on delete cascade,
  device_id  text   not null,
  change_id  text   not null,
  tbl        text   not null,
  row_id     text   not null,
  field      text   not null,
  value      jsonb,
  hlc        text   collate "C" not null,
  base_hlc   text   collate "C",
  created_at timestamptz not null default now()
);
create index change_log_owner_seq on public.change_log (owner_id, seq);

-- Idempotency ledger: includes rejected changes so retries never double-log conflicts.
create table public.applied_changes (
  owner_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  change_id text not null,
  primary key (owner_id, device_id, change_id)
);

create table public.sync_conflicts (
  id          bigserial primary key,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  tbl         text not null,
  row_id      text not null,
  field       text not null,
  lost_value  jsonb,
  lost_hlc    text collate "C" not null,
  winner_hlc  text collate "C" not null,
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);
create index sync_conflicts_owner on public.sync_conflicts (owner_id, created_at);

create table public.audit_log (
  id         bigserial primary key,
  owner_id   uuid not null references auth.users(id) on delete cascade,
  event      text not null,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.sync_fields     enable row level security;
alter table public.change_log      enable row level security;
alter table public.applied_changes enable row level security;
alter table public.sync_conflicts  enable row level security;
alter table public.audit_log       enable row level security;

-- Clients may READ their own rows. Nobody writes tables directly: all writes go through
-- apply_changes / resolve_conflict / log_audit (SECURITY DEFINER, owner taken from auth.uid()).
create policy sync_fields_read    on public.sync_fields    for select to authenticated using (owner_id = (select auth.uid()));
create policy change_log_read     on public.change_log     for select to authenticated using (owner_id = (select auth.uid()));
create policy sync_conflicts_read on public.sync_conflicts for select to authenticated using (owner_id = (select auth.uid()));
create policy audit_log_read      on public.audit_log      for select to authenticated using (owner_id = (select auth.uid()));
-- applied_changes: no policy => no client access at all.

revoke all on public.sync_fields, public.change_log, public.applied_changes, public.sync_conflicts, public.audit_log from anon, authenticated, public;
grant select on public.sync_fields, public.change_log, public.sync_conflicts, public.audit_log to authenticated;

-- ---------------------------------------------------------------------------------------
create or replace function public.apply_changes(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid        uuid := (select auth.uid());
  c          jsonb;
  v_tbl      text; v_row text; v_field text; v_hlc text; v_base text; v_dev text; v_cid text;
  v_val      jsonb;
  cur_hlc    text; cur_val jsonb;
  n_acc      int := 0; n_conf int := 0; n_dup int := 0;
  new_seq    bigint;
  allowed_tbl constant text[] := array['tasks','events']; -- add a table here when it starts to sync
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if jsonb_typeof(changes) is distinct from 'array' then raise exception 'changes must be a json array' using errcode = '22023'; end if;
  if jsonb_array_length(changes) > 500 then raise exception 'batch too large (max 500)' using errcode = '54000'; end if;

  -- Serialise writers per owner so seq order == commit order (no missed rows for pullers).
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  for c in select * from jsonb_array_elements(changes) loop
    v_tbl := c->>'tbl'; v_row := c->>'row_id'; v_field := c->>'field';
    v_hlc := c->>'hlc'; v_base := c->>'base_hlc'; v_dev := c->>'device_id'; v_cid := c->>'change_id';
    v_val := c->'value';
    if v_val = 'null'::jsonb then v_val := null; end if; -- JSON null == SQL NULL value

    if v_tbl is null or not (v_tbl = any (allowed_tbl)) then raise exception 'invalid table: %', v_tbl using errcode = '22023'; end if;
    if v_row is null or length(v_row) not between 1 and 200 then raise exception 'invalid row_id' using errcode = '22023'; end if;
    if v_field is null or v_field !~ '^[A-Za-z0-9_:\-]{1,100}$' then raise exception 'invalid field' using errcode = '22023'; end if;
    if v_hlc is null or v_hlc !~ '^[0-9a-f]{12}-[0-9a-f]{4}-.{1,100}$' then raise exception 'invalid hlc' using errcode = '22023'; end if;
    if v_base is not null and v_base !~ '^[0-9a-f]{12}-[0-9a-f]{4}-.{1,100}$' then raise exception 'invalid base_hlc' using errcode = '22023'; end if;
    if v_dev is null or v_cid is null or length(v_dev) > 100 or length(v_cid) > 100 then raise exception 'invalid device/change id' using errcode = '22023'; end if;
    if v_val is not null and pg_column_size(v_val) > 1048576 then raise exception 'value too large (max 1 MiB)' using errcode = '54000'; end if;

    insert into public.applied_changes(owner_id, device_id, change_id) values (uid, v_dev, v_cid)
      on conflict do nothing;
    if not found then n_dup := n_dup + 1; continue; end if;   -- retried delivery

    select f.hlc, f.value into cur_hlc, cur_val
      from public.sync_fields f where f.owner_id = uid and f.tbl = v_tbl and f.row_id = v_row and f.field = v_field;

    -- Same rule, same order as packages/sync_engine resolve():
    --   no current -> accept | same hlc -> duplicate | base = current -> accept
    --   else concurrent: higher hlc wins, the loser is recorded in sync_conflicts.
    declare
      found_cur boolean := found;
      accept    boolean;
    begin
      if not found_cur then
        accept := true;
      elsif v_hlc = cur_hlc then
        n_dup := n_dup + 1; continue;
      elsif v_base is not null and v_base = cur_hlc then
        accept := true;
      elsif v_hlc > cur_hlc then
        accept := true;
        insert into public.sync_conflicts(owner_id, tbl, row_id, field, lost_value, lost_hlc, winner_hlc)
          values (uid, v_tbl, v_row, v_field, cur_val, cur_hlc, v_hlc);
        n_conf := n_conf + 1;
      else
        accept := false;
        insert into public.sync_conflicts(owner_id, tbl, row_id, field, lost_value, lost_hlc, winner_hlc)
          values (uid, v_tbl, v_row, v_field, v_val, v_hlc, cur_hlc);
        n_conf := n_conf + 1;
      end if;

      if accept then
        insert into public.change_log(owner_id, device_id, change_id, tbl, row_id, field, value, hlc, base_hlc)
          values (uid, v_dev, v_cid, v_tbl, v_row, v_field, v_val, v_hlc, v_base)
          returning seq into new_seq;
        insert into public.sync_fields(owner_id, tbl, row_id, field, value, hlc, updated_seq)
          values (uid, v_tbl, v_row, v_field, v_val, v_hlc, new_seq)
          on conflict (owner_id, tbl, row_id, field)
          do update set value = excluded.value, hlc = excluded.hlc, updated_seq = excluded.updated_seq;
        n_acc := n_acc + 1;
      end if;
    end;
  end loop;

  return jsonb_build_object('accepted', n_acc, 'conflicts', n_conf, 'duplicates', n_dup,
    'seq', coalesce((select max(l.seq) from public.change_log l where l.owner_id = uid), 0));
end;
$$;

create or replace function public.resolve_conflict(conflict_id bigint)
returns void language sql security definer set search_path = '' as $$
  update public.sync_conflicts set resolved_at = now()
   where id = conflict_id and owner_id = (select auth.uid()) and resolved_at is null;
$$;

create or replace function public.log_audit(event text, meta jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if length(event) > 64 or pg_column_size(meta) > 8192 then raise exception 'invalid audit entry' using errcode = '22023'; end if;
  insert into public.audit_log(owner_id, event, meta) values ((select auth.uid()), event, meta);
end; $$;

revoke all on function public.apply_changes(jsonb), public.resolve_conflict(bigint), public.log_audit(text, jsonb) from public, anon;
grant execute on function public.apply_changes(jsonb), public.resolve_conflict(bigint), public.log_audit(text, jsonb) to authenticated;
