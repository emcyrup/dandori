-- ============================================================================
--  ナイトだんどり / SQL を流したあとに毎回流す仕上げ（何度流しても壊れません）
--
--  Supabase の service_role は「RLS を素通りできる」特別な役割ですが、
--  RDS ではその権限（BYPASSRLS）を付けられません。
--  かわりに、RLS が入っている表すべてに「service_role は全件OK」のポリシーを足します。
--  （service_role の鍵はサーバー側だけにあり、ブラウザには出ません）
-- ============================================================================
\set ON_ERROR_STOP on

do $$
declare r record;
begin
  for r in
    select n.nspname, c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('r', 'p') and c.relrowsecurity
       and n.nspname in ('public', 'app', 'storage')
  loop
    if not exists (select 1 from pg_policies
                    where schemaname = r.nspname and tablename = r.relname
                      and policyname = 'zz_service_role_all') then
      execute format(
        'create policy zz_service_role_all on %I.%I for all to service_role using (true) with check (true)',
        r.nspname, r.relname);
    end if;
  end loop;
end $$;

grant usage on schema public, app to service_role;
grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public, app to service_role;
grant select, insert, update, delete on all tables in schema app to service_role;

-- app の関数（security definer）が auth.users を見られるように
grant select on auth.users to postgres;

-- PostgREST に表と関数の一覧を読み直してもらう
notify pgrst, 'reload schema';
