-- ============================================================================
--  ナイトだんどり / SQL を流す前の下ごしらえ ― 単一ロールモード
--
--  2回目以降に 2_データベース を流し直すとき、前回の post-single.sql で付けた
--  FORCE ROW LEVEL SECURITY が効いたままだと、途中で止まります：
--    create or replace function で app.my_tenant() などの「素通りの印」が消え、
--    ポリシーも元の形に戻る → ポリシー → 関数 → 表 → ポリシー … の無限ループ
--    （stack depth limit exceeded）。初回は FORCE が無かったので通っていました。
--
--  そこで、流す前に FORCE を外して「初回と同じ状態」にします。
--  この間は表の持ち主（DB ユーザー）が RLS を素通りするので、db.sh は
--  この前後で画面からの API（PostgREST・ファイル置き場・関数）を止めています。
--  流し終わったら post-single.sql がもう一度 FORCE を付けます。
-- ============================================================================
\set ON_ERROR_STOP on
do $$
declare r record; n integer := 0;
begin
  for r in
    select n.nspname, c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('r', 'p') and c.relforcerowsecurity
       and n.nspname in ('public', 'app', 'storage')
  loop
    execute format('alter table %I.%I no force row level security', r.nspname, r.relname);
    n := n + 1;
  end loop;
  raise notice '表 % 件の FORCE ROW LEVEL SECURITY を、SQL を流す間だけ外しました', n;
end $$;
