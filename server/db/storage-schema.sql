-- ============================================================================
--  ナイトだんどり / ファイル置き場（storage スキーマ）の表
--
--  Supabase の Storage が自分で作る表のうち、だんどりが使うぶんだけを作ります。
--  supabase_storage_admin で流します（何度流しても壊れません）。
--    PGPASSWORD=... psql -U supabase_storage_admin -f server/db/storage-schema.sql
-- ============================================================================
\set ON_ERROR_STOP on
set search_path = storage, public;

create table if not exists storage.buckets (
  id                 text primary key,
  name               text not null unique,
  owner              uuid,
  public             boolean default false,
  avif_autodetection boolean default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  owner_id           text
);

create table if not exists storage.objects (
  id               uuid primary key default gen_random_uuid(),
  bucket_id        text references storage.buckets(id),
  name             text,
  owner            uuid,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata         jsonb,
  path_tokens      text[] generated always as (string_to_array(name, '/')) stored,
  version          text,
  owner_id         text,
  user_metadata    jsonb,
  unique (bucket_id, name)
);
create index if not exists idx_objects_bucket_name on storage.objects(bucket_id, name);

alter table storage.buckets enable row level security;
alter table storage.objects enable row level security;

-- 「a/b/c.txt」→ {a,b} のように、フォルダ部分を取り出す（RLS のポリシーで使う）
create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$
  select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1];
$$;
create or replace function storage.filename(name text) returns text
language sql immutable as $$
  select (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)];
$$;
create or replace function storage.extension(name text) returns text
language sql immutable as $$
  select reverse(split_part(reverse(storage.filename(name)), '.', 1));
$$;

grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.buckets, storage.objects to anon, authenticated, service_role;
grant execute on all functions in schema storage to anon, authenticated, service_role;
