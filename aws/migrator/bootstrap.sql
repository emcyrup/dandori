-- ============================================================================
--  ナイトだんどり / RDS の初期設定（最初に1回だけ。何度流しても壊れません）
--
--  Supabase のデータベースに最初から入っている「役割」と「権限」を、
--  素の PostgreSQL (RDS や自前のサーバー) に作ります。
--  DB の持ち主のユーザー（RDS なら postgres、自前サーバーなら ai_labo_dbuser など）で流します。
--  そのユーザーには CREATEROLE（または superuser）が必要です。
--
--  psql 変数で各ロールのパスワードを受け取ります：
--    :'authenticator_pw'  :'auth_admin_pw'  :'storage_admin_pw'
-- ============================================================================
\set ON_ERROR_STOP on

-- 流しているユーザーと DB の名前（以下の :"owner" / :"dbname"）
select current_user as owner, current_database() as dbname,
       (select rolcreaterole from pg_roles where rolname = current_user) as has_createrole \gset

-- 1. 役割（Supabase と同じ名前）
--    役割を作れる権限（CREATEROLE）が無いときは、この節は飛ばします。
--    その場合は server/db/依頼_DB権限.sql を DB 管理者に流してもらってください。
\if :has_createrole
-- パスワードを do ブロックの中で使えるように、いったん設定値に入れる（$$ の中では psql 変数が使えないため）
select set_config('dandori.authenticator_pw', :'authenticator_pw', false),
       set_config('dandori.auth_admin_pw',    :'auth_admin_pw',    false),
       set_config('dandori.storage_admin_pw', :'storage_admin_pw', false) \gset _
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  -- RDS では BYPASSRLS が付けられないので、service_role は post.sql の RLS ポリシーで全件を許可する
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role nologin noinherit; end if;
  -- PostgREST が使う接続ユーザー
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute format('create role authenticator login noinherit password %L', current_setting('dandori.authenticator_pw')); end if;
  -- GoTrue(ログイン) と Storage(ファイル) が、それぞれ自分の表を作るためのユーザー
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin')    then
    execute format('create role supabase_auth_admin login noinherit createrole password %L', current_setting('dandori.auth_admin_pw')); end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then
    execute format('create role supabase_storage_admin login noinherit createrole password %L', current_setting('dandori.storage_admin_pw')); end if;
  -- GoTrue / Storage の作業手順は「postgres」という名前の役割があることを前提にしている。
  -- RDS や普通のインストールにはあるが、無いサーバーもあるので、ログインできない形で作っておく
  if not exists (select 1 from pg_roles where rolname = 'postgres') then create role postgres nologin; end if;
end $$;

-- （すでにある役割のパスワードは変えません。同じ PostgreSQL に別店舗が動いているとき、
--   その店舗を壊さないためです。パスワードは最初の店舗と同じものを .env に入れてください）

grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to supabase_storage_admin;
-- DB の持ち主が auth / storage の表に触れるように（auth.users の参照、storage.objects のポリシー作成）
grant supabase_auth_admin, supabase_storage_admin to :"owner";

alter role supabase_auth_admin    set search_path = auth;
alter role supabase_storage_admin set search_path = storage;
alter role authenticator set statement_timeout = '8s';
alter role anon          set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';
\else
\echo '   役割を作る権限が無いので、役割の作成は飛ばします（管理者に作ってもらったものを使います）'
\endif

-- 2. 拡張機能（Supabase と同じく extensions スキーマに置く）
create schema if not exists extensions;
grant usage on schema extensions to :"owner", anon, authenticated, service_role, supabase_auth_admin, supabase_storage_admin;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto    with schema extensions;

-- 3. GoTrue / Storage の置き場所
create schema if not exists auth    authorization supabase_auth_admin;
create schema if not exists storage authorization supabase_storage_admin;
grant usage on schema auth, storage to :"owner", anon, authenticated, service_role;
grant create on database :"dbname" to supabase_auth_admin, supabase_storage_admin;

-- 4. public スキーマの既定の権限（Supabase と同じ）
--    新しく作った表は anon / authenticated / service_role に開き、実際の制限は RLS に任せる
grant usage on schema public to anon, authenticated, service_role;
alter default privileges for role :"owner" in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges for role :"owner" in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges for role :"owner" in schema public grant all on functions to anon, authenticated, service_role;
