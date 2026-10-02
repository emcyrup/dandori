-- ============================================================================
--  ナイトだんどり / 役割（ロール）を管理者（postgres）で作る
--
--  deploy.sh --init が、.env に DB_ADMIN_PASSWORD があるときに自動で流します。
--  手で流すときは：
--    PGPASSWORD=… psql -U postgres -d dandoriolivia \
--      -v app_user=ai_labo_dbuser -v authenticator_pw=… -v auth_admin_pw=… -v storage_admin_pw=… \
--      -f server/db/admin-roles.sql
--
--  何度流しても壊れません。すでにある役割のパスワードは変えません
--  （同じ PostgreSQL に複数店舗を置くとき、先に動いている店舗を壊さないため）。
-- ============================================================================
\set ON_ERROR_STOP on
select current_database() as dbname \gset

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'postgres')      then create role postgres nologin; end if;
end $$;

select not exists (select 1 from pg_roles where rolname = 'authenticator')          as new_authenticator,
       not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin')    as new_auth_admin,
       not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') as new_storage_admin \gset

\if :new_authenticator
create role authenticator login noinherit password :'authenticator_pw';
alter role authenticator set statement_timeout = '8s';
\endif
\if :new_auth_admin
create role supabase_auth_admin login noinherit createrole password :'auth_admin_pw';
alter role supabase_auth_admin set search_path = auth;
\endif
\if :new_storage_admin
create role supabase_storage_admin login noinherit createrole password :'storage_admin_pw';
alter role supabase_storage_admin set search_path = storage;
\endif

alter role anon          set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';

grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to supabase_storage_admin;
grant supabase_auth_admin, supabase_storage_admin to :"app_user";

-- この店舗の DB の持ち主を、アプリのユーザーに
alter database :"dbname" owner to :"app_user";

-- （Supabase から既存データを移すときに使う。PostgreSQL 15 以上）
select current_setting('server_version_num')::int >= 150000 as pg15 \gset
\if :pg15
grant set on parameter session_replication_role to :"app_user";
\endif
