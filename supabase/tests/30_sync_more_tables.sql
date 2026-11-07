-- tag_colors, smart_views and page_ink are accepted; other tables are still refused. Run via run.sh.
\set ON_ERROR_STOP on
\set A '11111111-1111-1111-1111-111111111111'
\set B '22222222-2222-2222-2222-222222222222'
insert into auth.users values ('33333333-3333-3333-3333-333333333333') on conflict do nothing;

create schema t3;
create or replace function t3.assert(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond,false) then raise exception 'ASSERT FAILED: %', msg; end if; end $$;
create or replace function t3.chg(tbl text, row_ text, f text, v jsonb, h text, dev text, cid text) returns jsonb language sql as $$
  select jsonb_build_object('tbl',tbl,'row_id',row_,'field',f,'value',v,'hlc',h,'device_id',dev,'change_id',cid) $$;
grant usage on schema t3 to public;
grant execute on all functions in schema t3 to public;

set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);

select t3.assert((apply_changes(jsonb_build_array(t3.chg('tag_colors','work','color','5','000000000001-0000-devA','devA','c1')))->>'accepted')::int = 1, 'tag colour accepted');
select t3.assert((apply_changes(jsonb_build_array(t3.chg('smart_views','work stuff','view','{"n":"Work stuff","s":"all","t":["work"],"o":"title"}','000000000002-0000-devA','devA','c2')))->>'accepted')::int = 1, 'saved view accepted');
select t3.assert((apply_changes(jsonb_build_array(t3.chg('page_ink','b1:3','strokes','[{"c":0,"w":0.004,"p":[0.1,0.1,0.2,0.2]}]','000000000003-0000-devA','devA','c3')))->>'accepted')::int = 1, 'drawing accepted');
-- clearing a colour is a normal change (value null)
select t3.assert((apply_changes(jsonb_build_array(t3.chg('tag_colors','work','color','null','000000000004-0000-devA','devA','c4')))->>'accepted')::int = 1, 'colour removal accepted');
select t3.assert((select count(*) from change_log) >= 4, 'all four changes are in the feed');
select t3.assert((select value from sync_fields where tbl = 'tag_colors' and row_id = 'work') is null, 'removed colour is stored as null');

-- other tables are still refused
do $$ begin
  begin
    perform apply_changes('[{"tbl":"books","row_id":"r","field":"f","value":1,"hlc":"000000000009-0000-a","device_id":"d","change_id":"c9"}]');
    raise exception 'ASSERT FAILED: books must not be accepted';
  exception when others then
    if sqlerrm not like '%invalid table%' then raise; end if;
  end;
end $$;

-- highlights and bookmarks (migration 20261109000000)
select t3.assert((apply_changes(jsonb_build_array(t3.chg('highlights','h1','body','{"b":"b1","p":3,"r":"[]","s":"text","at":1}','000000000005-0000-devA','devA','c5')))->>'accepted')::int = 1, 'highlight accepted');
select t3.assert((apply_changes(jsonb_build_array(t3.chg('bookmarks','b1:3','mark','{"l":"","at":1}','000000000006-0000-devA','devA','c6')))->>'accepted')::int = 1, 'bookmark accepted');
