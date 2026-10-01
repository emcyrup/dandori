-- ============================================================================
--  ログインするユーザーを、スタッフとして登録する
--  003_link_user.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--
--  【先にやること】
--    Supabase → Authentication → Users → Add user → Create new user
--    メールとパスワードを入れて作成（「Auto Confirm User」をオンに）
--
--  【そのあと】
--    このファイルを流してから、いちばん下の select を実行します。
-- ============================================================================

create or replace function app.link_staff(
  p_email  text,
  p_name   text,
  p_role   text default 'owner',      -- owner / manager / staff / driver
  p_tenant uuid default null           -- 省略すると、いちばん最初に作られた法人に入れます
) returns public.staff
language plpgsql security definer set search_path = public, app, auth
as $$
declare
  u_id uuid;
  t_id uuid;
  s    public.staff;
begin
  select id into u_id from auth.users where lower(email) = lower(p_email);
  if u_id is null then
    raise exception 'Authentication → Users に % が見つかりません。先にユーザーを作成してください', p_email;
  end if;

  if p_tenant is null then
    select id into t_id from public.tenant order by created_at limit 1;
  else
    t_id := p_tenant;
  end if;
  if t_id is null then
    raise exception '法人（tenant）が1件もありません。001_foundation.sql を先に実行してください';
  end if;

  insert into public.staff(tenant_id, auth_user_id, name, email, role)
  values (t_id, u_id, p_name, p_email, p_role)
  on conflict (auth_user_id) do update
    set name = excluded.name, role = excluded.role,
        email = excluded.email, is_active = true
  returning * into s;

  -- owner / manager は全店舗を見られるので所属登録は不要ですが、
  -- staff / driver は所属店舗を入れないと何も見えません。
  if s.role in ('staff','driver') then
    insert into public.staff_store(staff_id, store_id)
    select s.id, st.id from public.store st where st.tenant_id = t_id
    on conflict do nothing;
  end if;

  return s;
end;
$$;


-- ============================================================================
--  ここを自分のメールアドレスに書き換えて実行してください
-- ============================================================================

-- select name, role, tenant_id from app.link_staff('自分のメール@example.com', '鈴木', 'owner');


-- 確認用：
-- select s.name, s.role, t.name as tenant from public.staff s join public.tenant t on t.id = s.tenant_id;
