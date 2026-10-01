-- ============================================================================
--  ナイトだんどり / 実店舗のセットアップ
--  006_provision.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜005 を先に実行しておいてください）
--
--  新しいお客様（法人・店舗）を1行で用意するための関数です。
--  料金マスタのひな形も一緒に入るので、登録したその日から伝票が打てます。
--  何度実行しても壊れません。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. 料金マスタのひな形を入れる
--     すでに料金が1件でも入っている店舗には、何もしません。
-- ----------------------------------------------------------------------------
create or replace function app.seed_night_menu(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; n integer := 0;
begin
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;

  if exists (select 1 from public.night_menu where store_id = p_store) then
    return 0;
  end if;

  insert into public.night_menu(tenant_id, store_id, category, name, unit_price,
                                back_amount, back_rate, sort_order)
  values
    (st.tenant_id, p_store, 'set',        'セット（60分）',      8000,    0, 0, 10),
    (st.tenant_id, p_store, 'set',        'セット（90分）',     11000,    0, 0, 11),
    (st.tenant_id, p_store, 'extension',  '延長（30分）',        4000,    0, 0, 20),
    (st.tenant_id, p_store, 'nomination', '本指名',              3000, 1500, 0, 30),
    (st.tenant_id, p_store, 'nomination', '場内指名',            2000, 1000, 0, 31),
    (st.tenant_id, p_store, 'douhan',     '同伴',                5000, 2500, 0, 40),
    (st.tenant_id, p_store, 'drink',      'キャストドリンク',    1500,  700, 0, 50),
    (st.tenant_id, p_store, 'drink',      'シャンパン（小）',   15000,    0, 10, 51),
    (st.tenant_id, p_store, 'bottle',     'ボトル（焼酎）',     12000,    0,  5, 60),
    (st.tenant_id, p_store, 'bottle',     'ボトル（ウイスキー）',15000,   0,  5, 61),
    (st.tenant_id, p_store, 'food',       'フルーツ盛り',        5000,    0, 0, 70),
    (st.tenant_id, p_store, 'food',       '乾き物',              1500,    0, 0, 71),
    (st.tenant_id, p_store, 'other',      'カラオケ',             500,    0, 0, 80);

  get diagnostics n = row_count;
  return n;
end;
$$;


-- ----------------------------------------------------------------------------
--  2. 新しいお客様（法人＋1店舗目）を用意する
--
--     使い方の例：
--       select * from app.provision_tenant(
--         '株式会社○○',      -- 法人名
--         'ラウンジ○○ 本店',  -- 店舗名
--         20,                  -- サービス料 %
--         10,                  -- 消費税 %
--         '05:00',             -- 営業日の切り替え時刻
--         1052                 -- 地域の最低賃金（円/時）
--       );
-- ----------------------------------------------------------------------------
create or replace function app.provision_tenant(
  p_tenant_name text,
  p_store_name  text,
  p_service_rate numeric default 20,
  p_tax_rate     numeric default 10,
  p_day_cutoff   time    default '05:00',
  p_min_wage     integer default 0,
  p_trial_days   integer default 30
) returns table (tenant_id uuid, store_id uuid, menu_count integer)
language plpgsql security definer set search_path = public, app
as $$
declare t_id uuid; s_id uuid; n integer;
begin
  if exists (select 1 from public.tenant where name = p_tenant_name) then
    raise exception '同じ名前の法人がすでにあります：%', p_tenant_name;
  end if;

  insert into public.tenant(name, industry, plan, trial_ends_at)
  values (p_tenant_name, 'night', 'trial', current_date + p_trial_days)
  returning id into t_id;

  insert into public.store(tenant_id, name, day_cutoff, service_rate, tax_rate, min_wage)
  values (t_id, p_store_name, p_day_cutoff, p_service_rate, p_tax_rate, p_min_wage)
  returning id into s_id;

  n := app.seed_night_menu(s_id);

  return query select t_id, s_id, n;
end;
$$;


-- ----------------------------------------------------------------------------
--  3. 2店舗目以降を足す
-- ----------------------------------------------------------------------------
create or replace function app.provision_store(
  p_tenant     uuid,
  p_store_name text,
  p_copy_from  uuid default null      -- 料金をコピーしたい既存店舗（省略ならひな形）
) returns uuid
language plpgsql security definer set search_path = public, app
as $$
declare base public.store; s_id uuid;
begin
  if p_copy_from is not null then
    select * into base from public.store where id = p_copy_from and tenant_id = p_tenant;
    if not found then raise exception 'コピー元の店舗が見つかりません'; end if;
  end if;

  insert into public.store(tenant_id, name, day_cutoff, service_rate, tax_rate,
                           tax_included, min_wage, ui_theme)
  values (p_tenant, p_store_name,
          coalesce(base.day_cutoff, '05:00'),
          coalesce(base.service_rate, 20),
          coalesce(base.tax_rate, 10),
          coalesce(base.tax_included, false),
          coalesce(base.min_wage, 0),
          coalesce(base.ui_theme, 'standard'))
  returning id into s_id;

  if p_copy_from is not null then
    insert into public.night_menu(tenant_id, store_id, category, name, unit_price,
                                  back_amount, back_rate, service_apply, tax_apply, sort_order)
    select tenant_id, s_id, category, name, unit_price,
           back_amount, back_rate, service_apply, tax_apply, sort_order
      from public.night_menu where store_id = p_copy_from and is_active;
  else
    perform app.seed_night_menu(s_id);
  end if;

  return s_id;
end;
$$;


-- ----------------------------------------------------------------------------
--  4. デモのデータを消す
--     本番のお客様に渡す前の掃除用です。デモ法人ごと消えます。
--       select app.delete_demo();
-- ----------------------------------------------------------------------------
create or replace function app.delete_demo()
returns text
language plpgsql security definer set search_path = public, app
as $$
declare t_id uuid;
begin
  select id into t_id from public.tenant where name = 'デモ／ラウンジ彩';
  if t_id is null then return 'デモのデータはありません。'; end if;

  -- staff は auth.users と紐づいているので、先に外します
  update public.staff set is_active = false where tenant_id = t_id;
  delete from public.tenant where id = t_id;   -- 配下は cascade で消えます

  return 'デモのデータを削除しました。ログインしていたアカウントは、
別の法人に登録し直してください（app.link_staff）。';
end;
$$;


-- ----------------------------------------------------------------------------
--  5. 権限
--     これらは管理者（SQL Editor）から実行する想定です。
--     画面からは呼べないようにしてあります。
-- ----------------------------------------------------------------------------
revoke all on function
  app.provision_tenant(text, text, numeric, numeric, time, integer, integer),
  app.provision_store(uuid, text, uuid),
  app.delete_demo()
from authenticated, anon;

-- 料金のひな形だけは、画面（店舗を足したとき）からも呼べるようにします
create or replace function public.night_seed_menu(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '料金の初期設定は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  return app.seed_night_menu(p_store);
end;
$$;

grant execute on function app.seed_night_menu(uuid) to authenticated;
grant execute on function public.night_seed_menu(uuid) to authenticated;


-- ============================================================================
--  新しいお客様を入れるときの手順（コピーして使ってください）
--
--  ① 法人と店舗をつくる
--     select * from app.provision_tenant(
--       '株式会社サンプル', 'ラウンジ サンプル 本店', 20, 10, '05:00', 1052);
--
--  ② Authentication → Users でオーナーのアカウントを作る（Auto Confirm をオン）
--
--  ③ そのアカウントを、この法人のオーナーとして登録する
--     select name, role from app.link_staff(
--       'owner@example.com', '山田 太郎', 'owner',
--       (select id from public.tenant where name = '株式会社サンプル'));
--
--  ④ 店長・スタッフを足す場合も同じ（role を 'manager' や 'staff' に）
--
--  ⑤ あとは画面から。設定タブで料金とサービス料を直し、
--     給与画面のキャスト設定からキャストを登録すれば、その日から使えます。
-- ============================================================================
