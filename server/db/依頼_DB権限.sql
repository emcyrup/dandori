-- ============================================================================
--  【DB 管理者（サーバー提供元）さまへのお願い】
--  ナイトだんどり が使う PostgreSQL の役割（ロール）を作ってください。
--
--  背景：
--    このアプリは Supabase と同じしくみ（PostgREST / GoTrue）で動きます。
--    そのしくみは「anon / authenticated / service_role」などの役割を使って
--    データの見せ分け（Row Level Security）を行うため、役割の作成が必要です。
--    配布いただいた ai_labo_dbuser には CREATEROLE が無いため、こちらで作れません。
--
--  やりかた（どちらか）：
--    A. いちばん簡単： ai_labo_dbuser に一時的に CREATEROLE を付けていただく
--         ALTER ROLE ai_labo_dbuser CREATEROLE;
--       → こちらで初期設定を流したあと、外していただいて構いません
--         ALTER ROLE ai_labo_dbuser NOCREATEROLE;
--
--    B. 下の SQL を superuser で流していただく
--       （〈…〉の3か所のパスワードは、こちらから別途お伝えします）
--
--  ほかに必要なもの：
--    ・dandoriolivia の持ち主が ai_labo_dbuser であること
--         ALTER DATABASE dandoriolivia OWNER TO ai_labo_dbuser;
--    ・（Supabase から既存データを移す場合のみ）
--         GRANT SET ON PARAMETER session_replication_role TO ai_labo_dbuser;
-- ============================================================================

-- 画面からの接続に使う役割（ログインはしない）
create role anon          nologin noinherit;
create role authenticated nologin noinherit;
create role service_role  nologin noinherit;

-- データの受け口（PostgREST）が接続する役割
create role authenticator login noinherit password '〈AUTHENTICATOR_PASSWORD〉';

-- ログイン（GoTrue）とファイル置き場が、自分の表を作るための役割
create role supabase_auth_admin    login noinherit createrole password '〈AUTH_ADMIN_PASSWORD〉';
create role supabase_storage_admin login noinherit createrole password '〈STORAGE_ADMIN_PASSWORD〉';

-- 役割どうしの関係
grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to supabase_storage_admin;
grant supabase_auth_admin, supabase_storage_admin to ai_labo_dbuser;

alter role supabase_auth_admin    set search_path = auth;
alter role supabase_storage_admin set search_path = storage;
alter role authenticator          set statement_timeout = '8s';
alter role anon                   set statement_timeout = '3s';
alter role authenticated          set statement_timeout = '8s';

-- 「postgres」という名前の役割が無いサーバーでは、これも必要です（ログイン不可で作ります）
-- create role postgres nologin;
