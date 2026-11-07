-- Sync highlights and bookmarks too (still written only through apply_changes):
--   highlights : row_id = highlight id,        fields 'body' {b, p, r, s, at}, 'color', 'note', 'gone' (true = removed)
--   bookmarks  : row_id = '<book id>:<page>',  field  'mark' {l, at} (or null = removed)
-- Only the allow-list changes; the rest of the function is identical to 20261106000000_sync_core.sql.

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
  allowed_tbl constant text[] := array['tasks','events','tag_colors','smart_views','page_ink','highlights','bookmarks']; -- add a table here when it starts to sync
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
