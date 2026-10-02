-- ============================================================================
--  ナイトだんどり / SQL を流したあとの仕上げ ― 単一ロールモード
--
--  役割（anon / authenticated / service_role）が無いサーバーで、Supabase と同じ
--  「だれが何を見られるか」を保つための設定です。何度流しても壊れません。
--
--  考え方：
--   1. 画面からの直接の読み書き（PostgREST）は、表の持ち主で実行される。
--      持ち主は普通 RLS を素通りしてしまうので、全部の表に FORCE ROW LEVEL SECURITY を付けて
--      持ち主にも RLS が効くようにする。
--   2. Supabase では security definer の関数は RLS を素通りする。同じ振る舞いにするため、
--      app / public の関数には「関数の中では RLS を素通りしてよい」印を付ける。
--      印には application_name（だれでも変えられる標準の設定値）を使う。
--      ALTER FUNCTION ... SET は、その関数を実行している間だけ有効で、終われば元に戻る。
--      （独自の設定値 dandori.xxx は PostgreSQL 15 以降、管理者でないと関数に付けられない）
--   3. サーバー処理（service_role の鍵）は、鍵の中の "svc":true（setup.sh が付ける印）で判定する。
--      PostgREST は鍵の role の値を実際の DB ロール名に書き換えるので、role では見分けられない。
--      鍵の署名は PostgREST が確かめているので、この判定は信頼できる。
-- ============================================================================
\set ON_ERROR_STOP on

-- service_role の鍵で呼ばれているか（PostgREST が入れる request.jwt.claims を見る）
create or replace function app.is_service() returns boolean
language sql stable
as $$
  select coalesce(current_setting('request.jwt.claims', true), '') <> ''
     and (   coalesce((current_setting('request.jwt.claims', true))::jsonb ->> 'role', '') = 'service_role'
          or coalesce((current_setting('request.jwt.claims', true))::jsonb ->> 'svc', '') = 'true');
$$;

-- 関数の中では RLS を素通りしてよいか
create or replace function app.rls_bypass() returns boolean
language sql stable
as $$ select current_setting('application_name', true) = 'dandori_fn'; $$;

do $$
declare r record; n integer := 0;
begin
  -- 2. app / public の関数すべてに、素通りの印を付ける（auth スキーマは GoTrue のものなので触らない）
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('app', 'public') and p.prokind = 'f'
       and p.proname not in ('is_service', 'rls_bypass')
  loop
    execute format('alter function %s set application_name = %L', r.sig, 'dandori_fn');
    n := n + 1;
  end loop;
  raise notice '関数 % 件に、関数内では RLS を素通りする印を付けました', n;

  -- 1. + 3. 既存のポリシーを「関数内 または service_role なら即 OK、それ以外は元の条件」に書き換える。
  --    CASE で先に判定することで、条件の中の app.my_tenant() などが呼ばれなくなり、
  --    関数 → ポリシー → 関数 … の無限ループを防ぐ（Supabase の「関数内は RLS 素通り」と同じ振る舞い）
  n := 0;
  for r in
    select schemaname, tablename, policyname, permissive, cmd, qual, with_check
      from pg_policies
     where schemaname in ('public', 'app', 'storage')
       and policyname not like 'zz_%'
       and coalesce(qual, '') not like '%app.rls_bypass()%'
       and coalesce(with_check, '') not like '%app.rls_bypass()%'
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    execute format(
      'create policy %I on %I.%I as %s for %s to public %s %s',
      r.policyname, r.schemaname, r.tablename,
      case when r.permissive = 'PERMISSIVE' then 'permissive' else 'restrictive' end,
      r.cmd,
      case when r.qual is not null
           then format('using (case when app.rls_bypass() or app.is_service() then true else (%s) end)', r.qual)
           else '' end,
      case when r.with_check is not null
           then format('with check (case when app.rls_bypass() or app.is_service() then true else (%s) end)', r.with_check)
           else '' end);
    n := n + 1;
  end loop;
  raise notice 'ポリシー % 件を、関数内・service_role は素通りする形に書き換えました', n;

  -- RLS のある表すべてに：持ち主にも RLS を効かせ、ポリシーが1つも無い表にも「関数内・service_role は OK」を付ける
  n := 0;
  for r in
    select n.nspname, c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('r', 'p') and c.relrowsecurity
       and n.nspname in ('public', 'app', 'storage')
  loop
    execute format('alter table %I.%I force row level security', r.nspname, r.relname);
    execute format('drop policy if exists zz_service_role_all on %I.%I', r.nspname, r.relname);
    execute format('drop policy if exists zz_single_bypass on %I.%I', r.nspname, r.relname);
    execute format(
      'create policy zz_single_bypass on %I.%I for all to public
         using (app.rls_bypass() or app.is_service())
         with check (app.rls_bypass() or app.is_service())',
      r.nspname, r.relname);
    n := n + 1;
  end loop;
  raise notice '表 % 件に、持ち主にも RLS を効かせました', n;
end $$;

-- PostgREST に表と関数の一覧を読み直してもらう
notify pgrst, 'reload schema';
