-- ============================================================================
--  ナイトだんどり / 法令・名簿パック
--  005_roster.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001 → 002 → 003 → 004 を先に実行しておいてください）
--
--  従業者名簿と、年齢確認・本人確認の記録です。
--  何度実行しても壊れません。
--
--  ※ この仕組みは「確認した事実を記録に残す」ためのものです。
--    名簿の様式や保存期間の要件は、営業の種別と自治体によって変わります。
--    実際の運用に入る前に、行政書士にご確認ください。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. 従業者名簿に必要な項目を、キャストに足す
-- ----------------------------------------------------------------------------
alter table public.night_cast
  add column if not exists birth_date      date,
  add column if not exists address         text,
  add column if not exists phone           text,
  add column if not exists emergency_name  text,
  add column if not exists emergency_phone text,
  add column if not exists job_type        text default '接客',
  add column if not exists left_reason     text;

comment on column public.night_cast.birth_date is
  '生年月日。年齢確認の根拠になります。18歳未満は登録できません。';
comment on column public.night_cast.job_type is
  '従事する業務の種類（従業者名簿の記載事項）';


-- ----------------------------------------------------------------------------
--  2. 年齢の計算
-- ----------------------------------------------------------------------------
create or replace function app.age_on(p_birth date, p_on date default current_date)
returns integer
language sql immutable
as $$
  select case when p_birth is null then null
              else extract(year from age(p_on, p_birth))::integer end;
$$;


-- ----------------------------------------------------------------------------
--  3. 18歳未満は登録させない
--     生年月日が入っていて、雇入日（なければ今日）時点で18歳未満なら弾きます。
-- ----------------------------------------------------------------------------
create or replace function app.trg_cast_age_guard()
returns trigger language plpgsql as $$
declare a integer;
begin
  if new.birth_date is null then
    return new;
  end if;
  a := app.age_on(new.birth_date, coalesce(new.joined_on, current_date));
  if a < 18 then
    raise exception '18歳未満の方は登録できません（雇入日時点で%歳）', a;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cast_age_guard on public.night_cast;
create trigger trg_cast_age_guard
before insert or update of birth_date, joined_on on public.night_cast
for each row execute function app.trg_cast_age_guard();


-- ----------------------------------------------------------------------------
--  4. 本人確認・年齢確認の記録
--
--     身分証の「画像」は、この表には入れません。
--     保管する場合は流出時の被害が大きく、保管期間や削除の取り決めが別に要ります。
--     ここでは「いつ・誰が・何で確認したか」を残す形にしています。
-- ----------------------------------------------------------------------------
create table if not exists public.night_id_check (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant(id) on delete cascade,
  store_id     uuid not null references public.store(id) on delete cascade,
  cast_id      uuid not null references public.night_cast(id) on delete cascade,
  checked_on   date not null default current_date,
  doc_type     text not null,        -- 運転免許証／マイナンバーカード／パスポート／健康保険証＋補助書類 など
  method       text not null default 'original',  -- original(原本提示) / copy(写し) / video(オンライン)
  age_at_check integer,              -- 確認時点の年齢（自動で入ります）
  checked_by   uuid references public.staff(id) on delete set null,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_idcheck_cast on public.night_id_check(cast_id, checked_on desc);

alter table public.night_id_check enable row level security;
drop policy if exists p_night_id_check on public.night_id_check;
create policy p_night_id_check on public.night_id_check for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id));


-- ----------------------------------------------------------------------------
--  5. 本人確認を記録する
-- ----------------------------------------------------------------------------
create or replace function public.night_id_check_add(
  p_cast     uuid,
  p_doc_type text,
  p_method   text default 'original',
  p_on       date default current_date,
  p_note     text default null
) returns public.night_id_check
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; r public.night_id_check;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception '本人確認の記録は、店長以上の権限が必要です';
  end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if c.birth_date is null then
    raise exception '先に生年月日を登録してください';
  end if;

  insert into public.night_id_check(
    tenant_id, store_id, cast_id, checked_on, doc_type, method, age_at_check, checked_by, note)
  values (c.tenant_id, c.store_id, c.id, p_on, p_doc_type, p_method,
          app.age_on(c.birth_date, p_on), me.id, p_note)
  returning * into r;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (c.tenant_id, c.store_id, me.id, 'id_check', 'night_id_check', r.id::text,
          jsonb_build_object('cast', c.name, 'doc', p_doc_type, 'age', r.age_at_check));

  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  6. 従業者名簿
--     求められたときに、そのまま出せる形の一覧です。
-- ----------------------------------------------------------------------------
create or replace view public.v_employee_roster with (security_invoker = on) as
select
  c.id                              as cast_id,
  c.store_id,
  s.name                            as store_name,
  c.name                            as display_name,      -- 源氏名
  c.real_name,
  c.birth_date,
  app.age_on(c.birth_date)          as age,
  c.address,
  c.phone,
  c.emergency_name,
  c.emergency_phone,
  c.job_type,
  c.joined_on,
  c.left_on,
  c.left_reason,
  c.is_active,
  ck.checked_on                     as id_checked_on,
  ck.doc_type                       as id_doc_type,
  ck.method                         as id_method,
  -- 名簿として足りない項目があるか
  (c.real_name is null or c.birth_date is null or c.address is null
   or c.phone is null or c.joined_on is null)              as roster_incomplete,
  (ck.id is null)                                          as id_check_missing,
  (app.age_on(c.birth_date) is not null and app.age_on(c.birth_date) < 20) as under_20
from public.night_cast c
join public.store s on s.id = c.store_id
left join lateral (
  select * from public.night_id_check k
   where k.cast_id = c.id
   order by k.checked_on desc, k.created_at desc
   limit 1
) ck on true;


-- ----------------------------------------------------------------------------
--  7. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_id_check_add(uuid, text, text, date, text),
  app.age_on(date, date)
to authenticated;


-- ============================================================================
--  デモ用：名簿の項目を埋めておきます
-- ============================================================================
do $$
declare s uuid;
begin
  select id into s from public.store where name = '三宮本店' limit 1;
  if s is null then return; end if;

  update public.night_cast set
    real_name = '佐々木 彩',  birth_date = '2001-05-14',
    address = '神戸市中央区○○町1-2-3 ○○マンション501',
    phone = '090-0000-0001', emergency_name = '佐々木 母', emergency_phone = '078-000-0001',
    job_type = '接客'
  where store_id = s and name = 'あや' and real_name is null;

  update public.night_cast set
    real_name = '南 美波',    birth_date = '1998-11-02',
    address = '神戸市灘区○○1-1-1',
    phone = '090-0000-0002', job_type = '接客'
  where store_id = s and name = 'みなみ' and real_name is null;

  -- れい は、わざと名簿が未完成のまま残しています（画面で赤く出ます）
end $$;


-- ============================================================================
--  確認用
--
--   select display_name, real_name, age, job_type, id_checked_on,
--          roster_incomplete, id_check_missing, under_20
--     from public.v_employee_roster order by display_name;
-- ============================================================================
