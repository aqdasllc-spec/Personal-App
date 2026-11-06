-- Cloud books: every user sees and changes only their own rows and their own storage folder.
\set ON_ERROR_STOP on
\set A '11111111-1111-1111-1111-111111111111'
\set B '22222222-2222-2222-2222-222222222222'
set role authenticated;
select t.as_user(:'A');
insert into cloud_books(owner_id, id, title, size_bytes) values (:'A', 'b1', 'Deep Work', 1000);
insert into storage.objects(bucket_id, name) values ('books', :'A' || '/b1.pdf');
select t.throws($q$insert into cloud_books(owner_id, id) values ('22222222-2222-2222-2222-222222222222', 'x')$q$, 'row-level security');
select t.throws($q$insert into storage.objects(bucket_id, name) values ('books', '22222222-2222-2222-2222-222222222222/x.pdf')$q$, 'row-level security');
select t.throws($q$insert into storage.objects(bucket_id, name) values ('books', 'loose.pdf')$q$, 'row-level security');
select t.assert((select count(*) from cloud_books) = 1, 'A sees own book');
select t.assert((select count(*) from storage.objects) = 1, 'A sees own file');

select t.as_user(:'B');
select t.assert((select count(*) from cloud_books) = 0, 'B cannot see A''s books');
select t.assert((select count(*) from storage.objects) = 0, 'B cannot see A''s files');
delete from cloud_books where id = 'b1';
delete from storage.objects where name like '%b1.pdf';
update cloud_books set title = 'hacked';
reset role;
select t.assert((select count(*) from cloud_books where title = 'Deep Work') = 1, 'B could not change or delete A''s book');
select t.assert((select count(*) from storage.objects) = 1, 'B could not delete A''s file');

set role authenticated;
select t.as_user(:'A');
delete from storage.objects where name like '%b1.pdf';
delete from cloud_books where id = 'b1';
select t.assert((select count(*) from cloud_books) = 0 and (select count(*) from storage.objects) = 0, 'A can unsync (delete) own');
reset role;
\echo ALL CLOUD BOOK TESTS PASSED
