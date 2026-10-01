-- ============================================================================
--  だんどりシリーズ / のーとシリーズ 共通土台  +  ナイトだんどり（伝票・会計）
--  001_foundation.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               このファイルの中身を全部貼って Run
--
--  何度実行しても壊れないように書いてあります（作成済みはスキップ）。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  0. 拡張とスキーマ
-- ============================================================================

create extension if not exists "pgcrypto";      -- gen_random_uuid()
create schema if not exists app;                -- 補助関数を入れる場所


-- ============================================================================
--  1. 共通土台：法人・店舗・スタッフ・権限
--     ここは全業種（だんどり5本 ＋ のーと5本）で共有します
-- ============================================================================

-- 法人（契約の単位）
create table if not exists public.tenant (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,                       -- 法人名・屋号
  industry     text not null default 'night',       -- food/salon/pet/night/cast/michi/hoiku/...
  plan         text not null default 'trial',       -- trial/active/suspended
  trial_ends_at date,
  note         text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- 店舗
create table if not exists public.store (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant(id) on delete cascade,
  name         text not null,
  code         text,                                -- 社内の店舗コード（任意）
  tel          text,
  address      text,
  -- 営業日の切り替え時刻。深夜営業なので 05:00 を既定に。
  -- 「26時の伝票は前日の売上」を成立させるための設定です。
  day_cutoff   time not null default '05:00',
  -- 会計の既定値（店舗ごとに変えられます）
  service_rate numeric(5,2) not null default 0,     -- サービス料率 % 例:20.00
  tax_rate     numeric(5,2) not null default 10.00, -- 消費税率 %
  tax_included boolean not null default false,      -- 料金マスタが税込みかどうか
  ui_theme     text not null default 'standard',    -- standard/large/dark/simple（着せ替え）
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_store_tenant on public.store(tenant_id);

-- スタッフ（ログインする人）
--  auth_user_id は Supabase Auth のユーザーと紐づけます。
--  招待前（まだログインしていない人）は null のままで構いません。
create table if not exists public.staff (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  auth_user_id  uuid unique,                        -- auth.users.id
  name          text not null,
  email         text,
  role          text not null default 'staff',      -- owner/manager/staff/driver
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_staff_tenant on public.staff(tenant_id);
create index if not exists idx_staff_auth   on public.staff(auth_user_id);

-- スタッフの所属店舗（多店舗対応。owner/manager は全店舗を見られます）
create table if not exists public.staff_store (
  staff_id  uuid not null references public.staff(id) on delete cascade,
  store_id  uuid not null references public.store(id) on delete cascade,
  primary key (staff_id, store_id)
);

-- 操作ログ（誰がいつ何を変えたか）
create table if not exists public.audit_log (
  id          bigserial primary key,
  tenant_id   uuid,
  store_id    uuid,
  staff_id    uuid,
  action      text not null,                        -- insert/update/delete/close/print など
  target      text not null,                        -- テーブル名や画面名
  target_id   text,
  detail      jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists idx_audit_tenant_time on public.audit_log(tenant_id, created_at desc);


-- ============================================================================
--  2. ナイトだんどり：伝票・会計パック
-- ============================================================================

-- キャスト
create table if not exists public.night_cast (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  name          text not null,                      -- 源氏名
  real_name     text,
  hourly_wage   integer not null default 0,         -- 基本時給（円）
  -- 時給スライドの条件。例：
  -- [{"type":"nomination","from":10,"wage":3000},{"type":"sales","from":300000,"wage":3500}]
  wage_rules    jsonb not null default '[]'::jsonb,
  joined_on     date,
  left_on       date,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_cast_store on public.night_cast(store_id) where is_active;

-- お客様
create table if not exists public.night_customer (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenant(id) on delete cascade,
  store_id       uuid not null references public.store(id) on delete cascade,
  name           text not null,                     -- 呼称（「佐藤様」など）
  kana           text,
  company        text,
  tel            text,
  main_cast_id   uuid references public.night_cast(id) on delete set null,
  first_visit_on date,
  last_visit_on  date,
  visit_count    integer not null default 0,
  note           text,
  is_blocked     boolean not null default false,    -- お断り
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists idx_customer_store on public.night_customer(store_id);
create index if not exists idx_customer_last  on public.night_customer(store_id, last_visit_on desc);

-- 料金マスタ（セット・延長・指名・同伴・ドリンク・ボトル・フード）
create table if not exists public.night_menu (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  category      text not null,                      -- set/extension/nomination/douhan/drink/bottle/food/other
  name          text not null,
  unit_price    integer not null default 0,         -- 単価（円）
  -- キャストへのバック。金額と率の両方を持てます（どちらか片方でOK）
  back_amount   integer not null default 0,         -- 1点あたりのバック額（円）
  back_rate     numeric(5,2) not null default 0,    -- 売上に対するバック率 %
  -- このメニューにサービス料・税をかけるか
  service_apply boolean not null default true,
  tax_apply     boolean not null default true,
  sort_order    integer not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_menu_store on public.night_menu(store_id, category, sort_order);

-- 来店（＝卓／伝票の親）
create table if not exists public.night_visit (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenant(id) on delete cascade,
  store_id        uuid not null references public.store(id) on delete cascade,
  business_date   date not null,                    -- 営業日（day_cutoff で決まる日付）
  table_no        text,                             -- 卓番
  customer_id     uuid references public.night_customer(id) on delete set null,
  guest_name      text,                             -- 会員でない場合の呼称
  head_count      integer not null default 1,
  main_cast_id    uuid references public.night_cast(id) on delete set null, -- 担当
  entered_at      timestamptz not null default now(),
  left_at         timestamptz,
  status          text not null default 'open',     -- open/closed/void
  -- 会計の確定値（締めたときに書き込みます。あとから計算し直さないための保存です）
  subtotal        integer not null default 0,
  service_charge  integer not null default 0,
  tax             integer not null default 0,
  discount        integer not null default 0,
  total           integer not null default 0,
  paid_cash       integer not null default 0,
  paid_card       integer not null default 0,
  paid_credit     integer not null default 0,       -- 売掛（ツケ）にした額
  closed_by       uuid references public.staff(id) on delete set null,
  closed_at       timestamptz,
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_visit_store_date on public.night_visit(store_id, business_date desc);
create index if not exists idx_visit_open on public.night_visit(store_id) where status = 'open';

-- 伝票明細
create table if not exists public.night_visit_item (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  visit_id      uuid not null references public.night_visit(id) on delete cascade,
  menu_id       uuid references public.night_menu(id) on delete set null,
  category      text not null,
  name          text not null,                      -- 打刻時点のメニュー名（あとで変わっても伝票は動きません）
  unit_price    integer not null,                   -- 打刻時点の単価
  quantity      integer not null default 1,
  amount        integer not null,                   -- unit_price * quantity
  cast_id       uuid references public.night_cast(id) on delete set null,  -- 指名・ドリンクの対象
  back_amount   integer not null default 0,         -- この明細から発生したバック（円）
  service_apply boolean not null default true,
  tax_apply     boolean not null default true,
  punched_at    timestamptz not null default now(),
  punched_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_item_visit on public.night_visit_item(visit_id);
create index if not exists idx_item_cast  on public.night_visit_item(cast_id, punched_at desc);

-- 会計（1つの伝票に複数の支払い方法が混ざる場合に備えて明細で持ちます）
create table if not exists public.night_payment (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant(id) on delete cascade,
  store_id    uuid not null references public.store(id) on delete cascade,
  visit_id    uuid not null references public.night_visit(id) on delete cascade,
  method      text not null,                        -- cash/card/credit/other
  amount      integer not null,
  memo        text,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.staff(id) on delete set null
);
create index if not exists idx_payment_visit on public.night_payment(visit_id);

-- 売掛（ツケ）
create table if not exists public.night_receivable (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  customer_id   uuid references public.night_customer(id) on delete set null,
  visit_id      uuid references public.night_visit(id) on delete set null,
  occurred_on   date not null,
  amount        integer not null,                   -- 発生額
  paid_amount   integer not null default 0,         -- 入金済み
  balance       integer generated always as (amount - paid_amount) stored,
  due_on        date,
  status        text not null default 'open',       -- open/partial/settled/written_off
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_recv_store on public.night_receivable(store_id, status);
create index if not exists idx_recv_cust  on public.night_receivable(customer_id);

-- 売掛の入金履歴（催促の記録もここに残します）
create table if not exists public.night_receivable_log (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenant(id) on delete cascade,
  receivable_id  uuid not null references public.night_receivable(id) on delete cascade,
  kind           text not null,                     -- payment/remind/adjust
  amount         integer not null default 0,
  memo           text,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.staff(id) on delete set null
);
create index if not exists idx_recvlog on public.night_receivable_log(receivable_id, created_at desc);

-- 出勤（給与パックで本格的に使いますが、伝票側でも担当の紐づけに使います）
create table if not exists public.night_attendance (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  cast_id       uuid not null references public.night_cast(id) on delete cascade,
  business_date date not null,
  clock_in      timestamptz,
  clock_out     timestamptz,
  late_minutes  integer not null default 0,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (cast_id, business_date)
);
create index if not exists idx_att_store_date on public.night_attendance(store_id, business_date desc);

-- 日締め（現金の理論値と実査）
create table if not exists public.night_daily_close (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenant(id) on delete cascade,
  store_id       uuid not null references public.store(id) on delete cascade,
  business_date  date not null,
  sales_total    integer not null default 0,        -- 売上合計
  cash_expected  integer not null default 0,        -- 現金の理論値
  cash_counted   integer not null default 0,        -- 実際に数えた額
  cash_diff      integer generated always as (cash_counted - cash_expected) stored,
  card_total     integer not null default 0,
  credit_total   integer not null default 0,        -- 新規の売掛
  visit_count    integer not null default 0,
  note           text,
  closed_by      uuid references public.staff(id) on delete set null,
  closed_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (store_id, business_date)
);


-- ============================================================================
--  3. 補助関数
-- ============================================================================

-- ログイン中のスタッフ
create or replace function app.me()
returns public.staff
language sql stable security definer set search_path = public, app
as $$
  select * from public.staff where auth_user_id = auth.uid() and is_active limit 1;
$$;

-- ログイン中のスタッフの法人ID
create or replace function app.my_tenant()
returns uuid
language sql stable security definer set search_path = public, app
as $$
  select tenant_id from public.staff where auth_user_id = auth.uid() and is_active limit 1;
$$;

-- ログイン中のスタッフの権限
create or replace function app.my_role()
returns text
language sql stable security definer set search_path = public, app
as $$
  select role from public.staff where auth_user_id = auth.uid() and is_active limit 1;
$$;

-- この店舗を触っていいか（owner/manager は法人内の全店舗、それ以外は所属店舗のみ）
create or replace function app.can_store(p_store uuid)
returns boolean
language sql stable security definer set search_path = public, app
as $$
  select exists (
    select 1
    from public.staff s
    join public.store st on st.id = p_store and st.tenant_id = s.tenant_id
    where s.auth_user_id = auth.uid()
      and s.is_active
      and (
        s.role in ('owner','manager')
        or exists (select 1 from public.staff_store ss
                   where ss.staff_id = s.id and ss.store_id = p_store)
      )
  );
$$;

-- 営業日の計算（切り替え時刻より前なら前日扱い）
--   例： day_cutoff = 05:00 のとき、深夜2時の伝票は前日の営業日になります
create or replace function app.business_date(p_ts timestamptz, p_cutoff time)
returns date
language sql immutable
as $$
  select case
    when (p_ts at time zone 'Asia/Tokyo')::time < p_cutoff
      then ((p_ts at time zone 'Asia/Tokyo')::date - 1)
    else   ((p_ts at time zone 'Asia/Tokyo')::date)
  end;
$$;

-- updated_at の自動更新
create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'tenant','store','staff','night_cast','night_customer','night_menu',
    'night_visit','night_receivable','night_attendance','night_daily_close'
  ] loop
    execute format('drop trigger if exists trg_touch_%1$s on public.%1$s', t);
    execute format(
      'create trigger trg_touch_%1$s before update on public.%1$s
       for each row execute function app.touch_updated_at()', t);
  end loop;
end $$;


-- ============================================================================
--  4. 伝票の再計算
--     明細を足し引きしたあとに呼ぶと、親の金額を計算し直します。
--     金額は「保存された確定値」なので、料金マスタを変えても過去の伝票は動きません。
-- ============================================================================

create or replace function public.night_recalc_visit(p_visit uuid)
returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare
  v public.night_visit;
  st public.store;
  v_sub integer := 0;
  v_svc_base integer := 0;
  v_svc integer := 0;
  v_tax_base integer := 0;
  v_tax integer := 0;
begin
  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません: %', p_visit; end if;
  select * into st from public.store where id = v.store_id;

  select coalesce(sum(amount),0),
         coalesce(sum(amount) filter (where service_apply),0),
         coalesce(sum(amount) filter (where tax_apply),0)
    into v_sub, v_svc_base, v_tax_base
  from public.night_visit_item where visit_id = p_visit;

  v_svc := floor(v_svc_base * st.service_rate / 100.0);

  if st.tax_included then
    v_tax := 0;                                   -- 料金マスタが税込みなら内税として扱います
  else
    v_tax := floor((v_tax_base + v_svc) * st.tax_rate / 100.0);
  end if;

  update public.night_visit
     set subtotal = v_sub,
         service_charge = v_svc,
         tax = v_tax,
         total = greatest(v_sub + v_svc + v_tax - discount, 0)
   where id = p_visit
   returning * into v;

  return v;
end;
$$;

-- 明細を入れ替えたら自動で再計算
create or replace function app.trg_recalc_visit()
returns trigger language plpgsql security definer set search_path = public, app as $$
begin
  perform public.night_recalc_visit(coalesce(new.visit_id, old.visit_id));
  return null;
end;
$$;

drop trigger if exists trg_item_recalc on public.night_visit_item;
create trigger trg_item_recalc
after insert or update or delete on public.night_visit_item
for each row execute function app.trg_recalc_visit();


-- ============================================================================
--  5. 売掛の状態更新（入金を記録したら残高と状態を直します）
-- ============================================================================

create or replace function app.trg_recv_log()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare r public.night_receivable;
begin
  if new.kind = 'payment' then
    update public.night_receivable
       set paid_amount = paid_amount + new.amount
     where id = new.receivable_id
     returning * into r;

    update public.night_receivable
       set status = case
             when r.amount - r.paid_amount <= 0 then 'settled'
             when r.paid_amount > 0 then 'partial'
             else 'open' end
     where id = new.receivable_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_recv_log on public.night_receivable_log;
create trigger trg_recv_log
after insert on public.night_receivable_log
for each row execute function app.trg_recv_log();


-- ============================================================================
--  6. 行レベルセキュリティ（RLS）
--     他店・他法人のデータは、たとえURLを直接叩かれても見えません。
-- ============================================================================

alter table public.tenant                enable row level security;
alter table public.store                 enable row level security;
alter table public.staff                 enable row level security;
alter table public.staff_store           enable row level security;
alter table public.audit_log             enable row level security;
alter table public.night_cast            enable row level security;
alter table public.night_customer        enable row level security;
alter table public.night_menu            enable row level security;
alter table public.night_visit           enable row level security;
alter table public.night_visit_item      enable row level security;
alter table public.night_payment         enable row level security;
alter table public.night_receivable      enable row level security;
alter table public.night_receivable_log  enable row level security;
alter table public.night_attendance      enable row level security;
alter table public.night_daily_close     enable row level security;

-- 法人：自分の法人だけ。書き換えは owner のみ。
drop policy if exists p_tenant_sel on public.tenant;
create policy p_tenant_sel on public.tenant for select
  using (id = app.my_tenant());
drop policy if exists p_tenant_upd on public.tenant;
create policy p_tenant_upd on public.tenant for update
  using (id = app.my_tenant() and app.my_role() = 'owner')
  with check (id = app.my_tenant());

-- 店舗：法人内は見える。作成・変更は owner/manager のみ。
drop policy if exists p_store_sel on public.store;
create policy p_store_sel on public.store for select
  using (tenant_id = app.my_tenant());
drop policy if exists p_store_wr on public.store;
create policy p_store_wr on public.store for all
  using (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'))
  with check (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'));

-- スタッフ：法人内は見える。追加・変更は owner/manager のみ。
drop policy if exists p_staff_sel on public.staff;
create policy p_staff_sel on public.staff for select
  using (tenant_id = app.my_tenant());
drop policy if exists p_staff_wr on public.staff;
create policy p_staff_wr on public.staff for all
  using (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'))
  with check (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'));

drop policy if exists p_staffstore on public.staff_store;
create policy p_staffstore on public.staff_store for all
  using (exists (select 1 from public.staff s
                 where s.id = staff_store.staff_id and s.tenant_id = app.my_tenant()))
  with check (exists (select 1 from public.staff s
                 where s.id = staff_store.staff_id and s.tenant_id = app.my_tenant()));

-- 操作ログ：読めるのは owner/manager。書き込みは全員。消せません。
drop policy if exists p_audit_sel on public.audit_log;
create policy p_audit_sel on public.audit_log for select
  using (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'));
drop policy if exists p_audit_ins on public.audit_log;
create policy p_audit_ins on public.audit_log for insert
  with check (tenant_id = app.my_tenant());

-- 業務テーブル：所属店舗のデータだけ
do $$
declare t text;
begin
  foreach t in array array[
    'night_cast','night_customer','night_menu','night_visit','night_visit_item',
    'night_payment','night_receivable','night_attendance','night_daily_close'
  ] loop
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format(
      'create policy p_%1$s on public.%1$s for all
         using (tenant_id = app.my_tenant() and app.can_store(store_id))
         with check (tenant_id = app.my_tenant() and app.can_store(store_id))', t);
  end loop;
end $$;

-- 売掛ログは store_id を持たないので、親をたどって判定します
drop policy if exists p_night_receivable_log on public.night_receivable_log;
create policy p_night_receivable_log on public.night_receivable_log for all
  using (exists (select 1 from public.night_receivable r
                 where r.id = receivable_id
                   and r.tenant_id = app.my_tenant()
                   and app.can_store(r.store_id)))
  with check (exists (select 1 from public.night_receivable r
                 where r.id = receivable_id
                   and r.tenant_id = app.my_tenant()
                   and app.can_store(r.store_id)));


-- ============================================================================
--  7. 画面用のビュー
-- ============================================================================

-- 今あいている卓の一覧（ホール画面用）
-- security_invoker = on … ビュー越しでもRLSが効くようにします（これがないと素通りします）
create or replace view public.v_open_visit with (security_invoker = on) as
select v.id, v.store_id, v.business_date, v.table_no, v.head_count,
       coalesce(c.name, v.guest_name) as guest,
       ca.name as main_cast,
       v.entered_at,
       extract(epoch from (now() - v.entered_at))::integer / 60 as minutes,
       v.subtotal, v.service_charge, v.tax, v.total
from public.night_visit v
left join public.night_customer c on c.id = v.customer_id
left join public.night_cast ca on ca.id = v.main_cast_id
where v.status = 'open';

-- キャスト別の日次成績（給与パックの下ごしらえ）
create or replace view public.v_cast_daily with (security_invoker = on) as
select i.store_id,
       v.business_date,
       i.cast_id,
       ca.name as cast_name,
       count(*) filter (where i.category = 'nomination') as nominations,
       count(*) filter (where i.category = 'douhan')     as douhans,
       count(*) filter (where i.category = 'drink')      as drinks,
       sum(i.amount)      as sales,
       sum(i.back_amount) as back
from public.night_visit_item i
join public.night_visit v on v.id = i.visit_id and v.status = 'closed'
left join public.night_cast ca on ca.id = i.cast_id
where i.cast_id is not null
group by i.store_id, v.business_date, i.cast_id, ca.name;


-- ============================================================================
--  7-2. 権限の付与
--       ログイン済みユーザー（authenticated）が、RLS の範囲内で読み書きできるように。
--       実際にどこまで見えるかは、上の RLS が決めます。
-- ============================================================================

grant usage on schema app to authenticated, service_role;
grant execute on all functions in schema app to authenticated, service_role;
alter default privileges in schema app
  grant execute on functions to authenticated, service_role;

grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;

-- 未ログイン（anon）には一切触らせません
revoke all on all tables in schema public from anon;


-- ============================================================================
--  8. デモ用データ（営業で見せる用）
--     本番の法人を作るときは、この節は流さないでください。
--     ※ RLS を通すため、Supabase の SQL Editor（管理者権限）から実行します。
-- ============================================================================

do $$
declare
  t_id uuid;
  s_id uuid;
  c1 uuid; c2 uuid; c3 uuid;
  cu1 uuid;
  m_set uuid; m_ext uuid; m_nom uuid; m_dou uuid; m_drk uuid; m_btl uuid;
  v_id uuid;
begin
  -- すでにデモがあれば作りません
  if exists (select 1 from public.tenant where name = 'デモ／ラウンジ彩') then
    return;
  end if;

  insert into public.tenant(name, industry, plan)
       values ('デモ／ラウンジ彩', 'night', 'trial') returning id into t_id;

  insert into public.store(tenant_id, name, tel, day_cutoff, service_rate, tax_rate)
       values (t_id, '三宮本店', '078-000-0000', '05:00', 20.00, 10.00)
       returning id into s_id;

  insert into public.night_cast(tenant_id, store_id, name, hourly_wage, joined_on)
       values (t_id, s_id, 'あや', 2500, '2025-04-01') returning id into c1;
  insert into public.night_cast(tenant_id, store_id, name, hourly_wage, joined_on)
       values (t_id, s_id, 'みなみ', 2800, '2024-11-10') returning id into c2;
  insert into public.night_cast(tenant_id, store_id, name, hourly_wage, joined_on)
       values (t_id, s_id, 'れい', 2200, '2026-02-01') returning id into c3;

  insert into public.night_customer(tenant_id, store_id, name, company, main_cast_id,
                                    first_visit_on, last_visit_on, visit_count)
       values (t_id, s_id, '佐藤様', '佐藤建設', c1, '2025-06-12', current_date - 12, 18)
       returning id into cu1;
  insert into public.night_customer(tenant_id, store_id, name, main_cast_id,
                                    first_visit_on, last_visit_on, visit_count)
       values (t_id, s_id, '田中様', c2, '2026-01-20', current_date - 45, 6);

  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_amount, sort_order)
       values (t_id, s_id, 'set', 'セット（60分）', 8000, 0, 10) returning id into m_set;
  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_amount, sort_order)
       values (t_id, s_id, 'extension', '延長（30分）', 4000, 0, 20) returning id into m_ext;
  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_amount, sort_order)
       values (t_id, s_id, 'nomination', '本指名', 3000, 1500, 30) returning id into m_nom;
  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_amount, sort_order)
       values (t_id, s_id, 'douhan', '同伴', 5000, 2500, 40) returning id into m_dou;
  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_amount, sort_order)
       values (t_id, s_id, 'drink', 'キャストドリンク', 1500, 700, 50) returning id into m_drk;
  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_rate, sort_order)
       values (t_id, s_id, 'bottle', 'ボトル（焼酎）', 12000, 5.00, 60) returning id into m_btl;

  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, sort_order)
       values (t_id, s_id, 'food', 'フルーツ盛り', 5000, 70);

  -- あいている卓を1つ（画面を開いた瞬間に中身が見えるように）
  insert into public.night_visit(tenant_id, store_id, business_date, table_no,
                                 customer_id, head_count, main_cast_id, entered_at)
       values (t_id, s_id, app.business_date(now(), '05:00'), 'A-2',
               cu1, 2, c1, now() - interval '72 minutes')
       returning id into v_id;

  insert into public.night_visit_item(tenant_id, store_id, visit_id, menu_id, category, name,
                                      unit_price, quantity, amount, cast_id, back_amount)
  values
    (t_id, s_id, v_id, m_set, 'set',        'セット（60分）', 8000, 2, 16000, null, 0),
    (t_id, s_id, v_id, m_ext, 'extension',  '延長（30分）',   4000, 1,  4000, null, 0),
    (t_id, s_id, v_id, m_nom, 'nomination', '本指名',         3000, 1,  3000, c1, 1500),
    (t_id, s_id, v_id, m_drk, 'drink',      'キャストドリンク', 1500, 3,  4500, c1, 2100),
    (t_id, s_id, v_id, m_btl, 'bottle',     'ボトル（焼酎）', 12000, 1, 12000, c2, 600);

  perform public.night_recalc_visit(v_id);
end $$;


-- ============================================================================
--  実行後の確認用（このSELECTだけ別に流すと、デモ伝票の計算結果が見えます）
--
--   select table_no, guest, main_cast, minutes, subtotal, service_charge, tax, total
--     from public.v_open_visit;
--
--   期待値： 小計 39,500 ／ サービス料 7,900 ／ 税 4,740 ／ 合計 52,140
-- ============================================================================
