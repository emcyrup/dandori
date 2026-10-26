-- ============================================================================
--  ナイトだんどり / ログインの権限を「店長（管理者）」と「スタッフ」の2つに
--                   ＋ スタッフの LINE 連携は、店長の認証コードで
--  039_roles_line_auth.sql
--
--  貼り付け先： SQL Editor（001 … 038 のあと）。何度流しても壊れません。
--
--   1. 権限は 店長（中では owner。管理者）／スタッフ（staff）の2つ。
--      いままでの「店長（manager）」は店長（管理者）に、ドライバー・キャストはスタッフにそろえる
--   2. 店長・スタッフそれぞれが使える機能を、店長が設定画面で決められる（tenant.role_features）
--   3. スタッフが LINE をアプリにつなぐとき：お店の公式 LINE のトークに「店長の認証コード」を送り、
--      続けてログインのメールアドレスかお名前を送ると、そのスタッフに結びつく
-- ============================================================================
\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
--  1. 権限をそろえる
-- ----------------------------------------------------------------------------
do $$
declare n_m integer; n_s integer;
begin
  update public.staff set role = 'owner' where role = 'manager';
  get diagnostics n_m = row_count;
  update public.staff set role = 'staff' where role not in ('owner', 'staff');
  get diagnostics n_s = row_count;
  if n_m + n_s > 0 then
    raise notice '権限をそろえました：店長（管理者）へ % 人、スタッフへ % 人', n_m, n_s;
  end if;
  -- スタッフになった人は、所属店舗が要る（無ければ法人のぜんぶのお店に）
  insert into public.staff_store(staff_id, store_id)
  select s.id, st.id from public.staff s join public.store st on st.tenant_id = s.tenant_id
   where s.role = 'staff'
     and not exists (select 1 from public.staff_store ss where ss.staff_id = s.id)
  on conflict do nothing;
end $$;

create or replace function public.staff_role_set(p_staff uuid, p_role text)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; s public.staff; n integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role <> 'owner' then raise exception '権限を変えられるのは、店長（管理者）だけです'; end if;
  if p_role not in ('owner', 'staff') then raise exception '権限は「店長」か「スタッフ」です'; end if;

  select * into s from public.staff where id = p_staff;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  if s.tenant_id <> me.tenant_id then raise exception 'ほかの法人の方は、あつかえません'; end if;
  if s.id = me.id then raise exception 'ご自分の権限は、この画面からは変えられません'; end if;

  if s.role = 'owner' and p_role <> 'owner' then
    select count(*) into n from public.staff
     where tenant_id = s.tenant_id and role = 'owner' and is_active and id <> s.id;
    if n = 0 then raise exception '店長が1人もいなくなってしまいます。先に別の方を店長にしてください'; end if;
  end if;

  update public.staff set role = p_role where id = p_staff returning * into s;

  if s.role = 'staff' and not exists (select 1 from public.staff_store ss where ss.staff_id = s.id) then
    insert into public.staff_store(staff_id, store_id)
    select s.id, st.id from public.store st where st.tenant_id = s.tenant_id
    on conflict do nothing;
  end if;
  return s;
end;
$$;

create or replace function public.staff_add(
  p_store uuid, p_name text, p_role text default 'staff', p_email text default null)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; s public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role <> 'owner' then raise exception 'スタッフを足せるのは、店長（管理者）だけです'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  if nullif(btrim(coalesce(p_name, '')), '') is null then raise exception 'お名前を入れてください'; end if;
  if coalesce(p_role, 'staff') not in ('owner', 'staff') then raise exception '権限は「店長」か「スタッフ」です'; end if;

  select * into st from public.store where id = p_store;
  insert into public.staff(tenant_id, name, role, email, is_active)
  values (st.tenant_id, btrim(p_name), coalesce(p_role, 'staff'), nullif(btrim(coalesce(p_email, '')), ''), true)
  returning * into s;
  if s.role = 'staff' then
    insert into public.staff_store(staff_id, store_id) values (s.id, p_store) on conflict do nothing;
  end if;
  return s;
end;
$$;

-- ログインの管理の一覧に出す呼び名
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = 'public.staff_login_list(uuid)'::regprocedure;
  if position('guard039' in src) = 0 then
    src := replace(src,
      $r$case s.role when 'owner' then 'オーナー' when 'manager' then '店長'$r$,
      $r$case s.role when 'owner' then '店長' when 'manager' then '店長'$r$);
    src := replace(src, $r$when 'driver' then 'ドライバー' else 'スタッフ' end$r$,
                        $r$else 'スタッフ' end /* guard039 */$r$);
    if position('guard039' in src) > 0 then
      execute format('create or replace function public.staff_login_list(p_store uuid) returns %s
        language plpgsql stable security definer set search_path = public, app as %L',
        pg_get_function_result('public.staff_login_list(uuid)'::regprocedure), src);
    end if;
  end if;
end $$;

-- ----------------------------------------------------------------------------
--  2. 権限ごとに使える機能（店長が決める）
--     形：{"owner": {"sales.html": true, ...}, "staff": {"index.html": true, "payroll.html#attend": true, ...}}
--     書いていない機能は、画面の決まり（menu の既定）に従う
-- ----------------------------------------------------------------------------
alter table public.tenant add column if not exists role_features jsonb not null default '{}'::jsonb;

create or replace function public.role_features_get()
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare me public.staff; t public.tenant;
begin
  select * into me from app.me();
  if me.id is null then return jsonb_build_object('role', null, 'features', '{}'::jsonb); end if;
  select * into t from public.tenant where id = me.tenant_id;
  return jsonb_build_object(
    'role', case when me.role in ('owner', 'manager') then 'owner' else 'staff' end,
    'features', coalesce(t.role_features, '{}'::jsonb),
    'can_edit', me.role = 'owner');
end;
$$;
grant execute on function public.role_features_get() to authenticated;

create or replace function public.role_features_set(p_features jsonb)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; r text; k text; v jsonb; clean jsonb := '{}'::jsonb; part jsonb;
begin
  select * into me from app.me();
  if me.id is null or me.role <> 'owner' then raise exception '機能の設定は、店長（管理者）だけができます'; end if;
  if jsonb_typeof(p_features) <> 'object' then raise exception '形が変です'; end if;
  foreach r in array array['owner', 'staff'] loop
    part := '{}'::jsonb;
    if jsonb_typeof(p_features -> r) = 'object' then
      for k, v in select * from jsonb_each(p_features -> r) loop
        if k !~ '^[a-z0-9_.-]{1,40}(#[a-z0-9_-]{1,30})?$' or jsonb_typeof(v) <> 'boolean' then continue; end if;
        part := part || jsonb_build_object(k, v);
      end loop;
    end if;
    clean := clean || jsonb_build_object(r, part);
  end loop;
  -- 店長が自分を締め出さないように
  clean := jsonb_set(clean, '{owner,admin.html}', 'true'::jsonb);
  clean := jsonb_set(clean, '{owner,login.html}', 'true'::jsonb);
  update public.tenant set role_features = clean where id = me.tenant_id;
  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, null, me.id, 'role_features_set', 'tenant', me.tenant_id::text, clean);
  return public.role_features_get();
end;
$$;
grant execute on function public.role_features_set(jsonb) to authenticated;

-- ----------------------------------------------------------------------------
--  3. LINE 連携：店長の認証コード
-- ----------------------------------------------------------------------------
create table if not exists public.line_auth_code (
  tenant_id  uuid primary key references public.tenant(id) on delete cascade,
  code       text not null,
  updated_by uuid references public.staff(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.line_auth_code enable row level security;   -- ポリシー無し：関数からだけ

alter table public.line_link add column if not exists auth_state  text;
alter table public.line_link add column if not exists auth_at     timestamptz;
alter table public.line_link add column if not exists auth_fails  integer not null default 0;
alter table public.line_link add column if not exists auth_locked timestamptz;
alter table public.staff     add column if not exists line_user_id text;

create or replace function app.new_line_code() returns text
language sql volatile as $$
  -- gen_random_uuid は強い乱数（PostgreSQL 13 以降は標準。拡張のスキーマに左右されない）
  select lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000))::text, 6, '0');
$$;

-- 店長が見る（無ければ作る）
create or replace function public.line_auth_code_get(p_reset boolean default false)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.line_auth_code;
begin
  select * into me from app.me();
  if me.id is null or me.role <> 'owner' then raise exception '認証コードは、店長（管理者）だけが見られます'; end if;
  select * into c from public.line_auth_code where tenant_id = me.tenant_id;
  if not found or p_reset then
    insert into public.line_auth_code(tenant_id, code, updated_by, updated_at)
    values (me.tenant_id, app.new_line_code(), me.id, now())
    on conflict (tenant_id) do update set code = excluded.code, updated_by = excluded.updated_by, updated_at = now()
    returning * into c;
  end if;
  return jsonb_build_object('code', c.code, 'updated_at', c.updated_at);
end;
$$;
grant execute on function public.line_auth_code_get(boolean) to authenticated;

-- LINE のトークに来た文字を見て、認証コード → 本人確認 → 結びつけ（入口の LINE Webhook からだけ呼ぶ）
create or replace function public.line_auth_message(p_tenant uuid, p_line_user_id text, p_text text)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  l public.line_link; c public.line_auth_code; t text; rest text := null; s public.staff;
  n integer; k text; tbl text; sid uuid; sname text; cnt integer; subj_kind text; subj_id uuid;
begin
  if not app.is_service() then raise exception 'この関数はサーバーの中からだけ使えます'; end if;
  select * into l from public.line_link where tenant_id = p_tenant and line_user_id = p_line_user_id;
  if not found or l.subject_id is not null then return jsonb_build_object('handled', false); end if;

  -- 全角の数字・空白をそろえる
  t := btrim(translate(coalesce(p_text, ''), '０１２３４５６７８９　', '0123456789 '));

  if l.auth_locked is not null and l.auth_locked > now() then
    return jsonb_build_object('handled', true, 'reply',
      '認証コードのまちがいが続いたので、しばらく受け付けを止めています。1時間ほどたってから、もう一度お試しください。');
  end if;

  select * into c from public.line_auth_code where tenant_id = p_tenant;

  -- 「123456 ゆいか」のように、コードと名前を一度に送ってもよい
  if t ~ '^[0-9]{6}(\s+.+)?$' then
    if c.code is not null and split_part(t, ' ', 1) = c.code then
      update public.line_link set auth_state = 'code_ok', auth_at = now(), auth_fails = 0, auth_locked = null where id = l.id;
      l.auth_state := 'code_ok'; l.auth_at := now();
      rest := nullif(btrim(substr(t, 7)), '');
      if rest is null then
        return jsonb_build_object('handled', true, 'reply',
          '認証できました。' || E'\n\n' ||
          'つづけて、アプリのログインに使っているメールアドレスか、名簿のお名前を送ってください（30分以内）。');
      end if;
    else
      update public.line_link
         set auth_fails = auth_fails + 1,
             auth_locked = case when auth_fails + 1 >= 5 then now() + interval '1 hour' else null end
       where id = l.id;
      return jsonb_build_object('handled', true, 'reply',
        '認証コードがちがうようです。店長に、いまの認証コードを確かめてください。');
    end if;
  end if;

  if l.auth_state is distinct from 'code_ok' or l.auth_at < now() - interval '30 minutes' then
    return jsonb_build_object('handled', false);
  end if;
  rest := coalesce(rest, t);

  -- 本人をさがす：ログインのメール → ログインの名前 → 名簿（キャストなど）の名前
  select count(*) into cnt from public.staff
   where tenant_id = p_tenant and is_active and lower(email) = lower(rest);
  if cnt = 1 then
    select * into s from public.staff where tenant_id = p_tenant and is_active and lower(email) = lower(rest);
  else
    select count(*) into cnt from public.staff where tenant_id = p_tenant and is_active and name = rest;
    if cnt = 1 then
      select * into s from public.staff where tenant_id = p_tenant and is_active and name = rest;
    end if;
  end if;

  if s.id is not null then
    -- そのログインに結びついた名簿の行（あれば）
    foreach k in array array['night_cast', 'cast_member', 'food_staff', 'salon_staff', 'pet_staff'] loop
      tbl := app.subject_table(k);
      if tbl is null or to_regclass(tbl) is null or subj_id is not null then continue; end if;
      begin
        execute format('select id from %s where tenant_id = $1 and (staff_id = $2 or (email is not null and $3 <> '''' and lower(email) = lower($3))) limit 1', tbl)
          into sid using p_tenant, s.id, coalesce(s.email, '');
      exception when undefined_column then
        execute format('select id from %s where tenant_id = $1 and email is not null and $2 <> '''' and lower(email) = lower($2) limit 1', tbl)
          into sid using p_tenant, coalesce(s.email, '');
      end;
      if sid is not null then subj_kind := k; subj_id := sid; end if;
    end loop;
    sname := s.name;
    if s.line_user_id is not null and s.line_user_id <> p_line_user_id then
      return jsonb_build_object('handled', true, 'reply',
        sname || ' さんには、もう別の LINE がつながっています。つなぎ直すときは、店長に外してもらってください。');
    end if;
  else
    -- ログインが無い方：名簿の名前で（同じ名前が2人以上なら、店長に）
    foreach k in array array['night_cast', 'cast_member', 'food_staff', 'salon_staff', 'pet_staff'] loop
      tbl := app.subject_table(k);
      if tbl is null or to_regclass(tbl) is null then continue; end if;
      execute format('select count(*), min(id::text)::uuid from %s where tenant_id = $1 and is_active and name = $2', tbl)
        into n, sid using p_tenant, rest;
      if n > 1 or (n = 1 and subj_id is not null) then
        return jsonb_build_object('handled', true, 'reply',
          '同じお名前の方が名簿に何人かいます。ログインのメールアドレスを送るか、店長に結びつけてもらってください。');
      end if;
      if n = 1 then subj_kind := k; subj_id := sid; end if;
    end loop;
    if subj_id is null then
      return jsonb_build_object('handled', true, 'reply',
        '「' || left(rest, 40) || '」は見つかりませんでした。' || E'\n' ||
        'アプリのログインに使っているメールアドレスか、名簿のお名前をそのまま送ってください。');
    end if;
    sname := app.subject_name(subj_kind, subj_id);
  end if;

  -- 名簿の行に、もう別の LINE がついていたら止める
  if subj_id is not null then
    execute format('select line_user_id from %s where id = $1', app.subject_table(subj_kind)) into k using subj_id;
    if k is not null and k <> p_line_user_id then
      return jsonb_build_object('handled', true, 'reply',
        sname || ' さんには、もう別の LINE がつながっています。つなぎ直すときは、店長に外してもらってください。');
    end if;
  end if;

  -- 結びつける（同じ LINE がほかの人についていたら外す）
  update public.staff set line_user_id = null where tenant_id = p_tenant and line_user_id = p_line_user_id;
  if s.id is not null then update public.staff set line_user_id = p_line_user_id where id = s.id; end if;
  if subj_id is not null then
    execute format('update %s set line_user_id = $1 where id = $2 and tenant_id = $3', app.subject_table(subj_kind))
      using p_line_user_id, subj_id, p_tenant;
  end if;
  update public.line_link
     set subject_kind = coalesce(subj_kind, 'staff'), subject_id = coalesce(subj_id, s.id),
         linked_by = null, linked_at = now(), auth_state = 'linked', auth_fails = 0
   where id = l.id;
  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (p_tenant, null, s.id, 'line_link_by_code', 'line_link', l.id::text,
          jsonb_build_object('name', sname, 'subject_kind', coalesce(subj_kind, 'staff')));

  return jsonb_build_object('handled', true, 'linked', true, 'reply',
    sname || ' さんとして、アプリとつながりました。' || E'\n\n' ||
    'これから、このトークでシフト希望が出せます（「ヘルプ」と送ると使い方が出ます）。給与明細や確定シフトのお知らせも届きます。');
end;
$$;
revoke all on function public.line_auth_message(uuid, text, text) from public;

-- 店長が手で外す（つなぎ直し用）
create or replace function public.line_unlink_staff(p_staff uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; s public.staff; k text; tbl text;
begin
  select * into me from app.me();
  if me.id is null or me.role <> 'owner' then raise exception 'LINE を外せるのは、店長（管理者）だけです'; end if;
  select * into s from public.staff where id = p_staff and tenant_id = me.tenant_id;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  if s.line_user_id is null then return jsonb_build_object('ok', true); end if;
  foreach k in array array['night_cast', 'cast_member', 'food_staff', 'salon_staff', 'pet_staff'] loop
    tbl := app.subject_table(k);
    if tbl is null or to_regclass(tbl) is null then continue; end if;
    execute format('update %s set line_user_id = null where tenant_id = $1 and line_user_id = $2', tbl)
      using me.tenant_id, s.line_user_id;
  end loop;
  update public.line_link set subject_kind = null, subject_id = null, auth_state = null, linked_at = null
   where tenant_id = me.tenant_id and line_user_id = s.line_user_id;
  update public.staff set line_user_id = null where id = s.id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.line_unlink_staff(uuid) to authenticated;

notify pgrst, 'reload schema';
