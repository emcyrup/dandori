-- ============================================================================
--  ナイトだんどり / RDS の初期設定（最初に1回だけ。何度流しても壊れません）
--
--  Supabase のデータベースに最初から入っている「役割」と「権限」を、
--  素の PostgreSQL (RDS) に作ります。RDS のマスターユーザー(postgres)で流します。
--
--  psql 変数で各ロールのパスワードを受け取ります：
--    :'authenticator_pw'  :'auth_admin_pw'  :'storage_admin_pw'
-- ============================================================================
\set ON_ERROR_STOP on

-- 1. 役割（Supabase と同じ名前）
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  -- RDS では BYPASSRLS が付けられないので、service_role は post.sql の RLS ポリシーで全件を許可する
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role nologin noinherit; end if;
  -- PostgREST が使う接続ユーザー
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator login noinherit; end if;
  -- GoTrue(ログイン) と Storage(ファイル) が、それぞれ自分の表を作るためのユーザー
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin')    then create role supabase_auth_admin login noinherit createrole; end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then create role supabase_storage_admin login noinherit createrole; end if;
end $$;

alter role authenticator          password :'authenticator_pw';
alter role supabase_auth_admin    password :'auth_admin_pw';
alter role supabase_storage_admin password :'storage_admin_pw';

grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to supabase_storage_admin;
-- postgres が auth / storage の表に触れるように（auth.users の参照、storage.objects のポリシー作成）
grant supabase_auth_admin, supabase_storage_admin to postgres;

alter role supabase_auth_admin    set search_path = auth;
alter role supabase_storage_admin set search_path = storage;
alter role authenticator set statement_timeout = '8s';
alter role anon          set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';

-- 2. 拡張機能（Supabase と同じく extensions スキーマに置く）
create schema if not exists extensions;
grant usage on schema extensions to postgres, anon, authenticated, service_role, supabase_auth_admin, supabase_storage_admin;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto    with schema extensions;

-- 3. GoTrue / Storage の置き場所
create schema if not exists auth    authorization supabase_auth_admin;
create schema if not exists storage authorization supabase_storage_admin;
grant usage on schema auth, storage to postgres, anon, authenticated, service_role;
grant create on database postgres to supabase_auth_admin, supabase_storage_admin;

-- 4. public スキーマの既定の権限（Supabase と同じ）
--    新しく作った表は anon / authenticated / service_role に開き、実際の制限は RLS に任せる
grant usage on schema public to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role;
