-- Per-book cloud copies (optional, user-controlled).
--   * storage bucket `books` (private): the PDF at  <owner uid>/<book id>.pdf
--   * public.cloud_books : one metadata row per uploaded book, so another device can list/download it
-- Each user can only touch their own folder / rows. Deleting ("unsync") removes both.

create table public.cloud_books (
  owner_id   uuid   not null references auth.users(id) on delete cascade,
  id         text   not null check (length(id) between 1 and 100),
  title      text   not null default '' check (length(title) <= 500),
  author     text   not null default '' check (length(author) <= 500),
  page_count integer not null default 0,
  size_bytes bigint  not null default 0,
  sha256     text   not null default '' check (length(sha256) <= 64),
  created_at timestamptz not null default now(),
  primary key (owner_id, id)
);
alter table public.cloud_books enable row level security;
create policy cloud_books_select on public.cloud_books for select to authenticated using (owner_id = (select auth.uid()));
create policy cloud_books_insert on public.cloud_books for insert to authenticated with check (owner_id = (select auth.uid()));
create policy cloud_books_update on public.cloud_books for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy cloud_books_delete on public.cloud_books for delete to authenticated using (owner_id = (select auth.uid()));
revoke all on public.cloud_books from anon, authenticated, public;
grant select, insert, update, delete on public.cloud_books to authenticated;

-- Private bucket for the PDFs (no per-bucket size cap here: your plan's file-size limit applies).
insert into storage.buckets (id, name, public) values ('books', 'books', false) on conflict (id) do nothing;

create policy books_read   on storage.objects for select to authenticated using (bucket_id = 'books' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy books_insert on storage.objects for insert to authenticated with check (bucket_id = 'books' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy books_update on storage.objects for update to authenticated using (bucket_id = 'books' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy books_delete on storage.objects for delete to authenticated using (bucket_id = 'books' and (storage.foldername(name))[1] = (select auth.uid())::text);
