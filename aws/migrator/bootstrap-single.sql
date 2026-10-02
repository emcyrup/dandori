-- ============================================================================
--  ナイトだんどり / DB の初期設定 ― 単一ロールモード（役割を作れないサーバー向け）
--
--  DB のユーザーが1つしか無く（例：ai_labo_dbuser）、anon / authenticated などの
--  役割を作れないときに、bootstrap.sql の代わりに流します。
--  ログイン（GoTrue）・ファイル置き場・データの受け口（PostgREST）は、すべてこの1ユーザーで動きます。
--  何度流しても壊れません。
-- ============================================================================
\set ON_ERROR_STOP on
select current_user as owner, current_database() as dbname \gset

-- 拡張機能（Supabase と同じく extensions スキーマに置く）
create schema if not exists extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto    with schema extensions;

-- ログイン（GoTrue）とファイル置き場の置き場所。持ち主はこのユーザー自身
create schema if not exists auth;
create schema if not exists storage;
