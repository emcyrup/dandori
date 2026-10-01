-- ============================================================================
--  ナイトだんどり / 送りパック
--  010_rides.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜006、009 を先に実行しておいてください）
--
--  閉店後の送りを、エリア・順番・ドライバーで組み立てて記録します。
--  地図APIは使いません（従量課金が発生しないよう、順番は手で並べ替える方式です）。
--  何度実行しても壊れません。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. エリア（送り先の区分と、その送り代）
-- ----------------------------------------------------------------------------
create table if not exists public.night_area (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenant(id) on delete cascade,
  store_id   uuid not null references public.store(id) on delete cascade,
  name       text not null,                 -- 三宮・元町／灘・六甲／明石方面 など
  fee        integer not null default 0,    -- お客様からいただく送り代
  driver_fee integer not null default 0,    -- ドライバーへ支払う1件あたりの額
  sort_order integer not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_area_store on public.night_area(store_id, sort_order);


-- ----------------------------------------------------------------------------
--  2. 送り
--     お客様の送りと、キャストの送りの両方を同じ表で扱います。
-- ----------------------------------------------------------------------------
create table if not exists public.night_ride (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  business_date date not null,
  subject       text not null default 'customer',   -- customer / cast / other
  customer_id   uuid references public.night_customer(id) on delete set null,
  cast_id       uuid references public.night_cast(id) on delete set null,
  label         text,                       -- 上記で表せない場合の呼称
  visit_id      uuid references public.night_visit(id) on delete set null,
  area_id       uuid references public.night_area(id) on delete set null,
  destination   text,                       -- 具体的な行き先（自宅・駅名など）
  head_count    integer not null default 1,
  fee           integer not null default 0, -- お客様からいただく額
  driver_fee    integer not null default 0, -- ドライバーへ支払う額
  driver_id     uuid references public.staff(id) on delete set null,
  seq           integer not null default 0, -- 回る順番
  status        text not null default 'waiting',  -- waiting / onboard / done / canceled
  requested_at  timestamptz not null default now(),
  departed_at   timestamptz,
  arrived_at    timestamptz,
  note          text,
  created_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_ride_day on public.night_ride(store_id, business_date, seq);
create index if not exists idx_ride_open on public.night_ride(store_id)
  where status in ('waiting','onboard');

drop trigger if exists trg_touch_night_ride on public.night_ride;
create trigger trg_touch_night_ride before update on public.night_ride
for each row execute function app.touch_updated_at();


-- ----------------------------------------------------------------------------
--  3. RLS
-- ----------------------------------------------------------------------------
alter table public.night_area enable row level security;
alter table public.night_ride enable row level security;

do $$
declare t text;
begin
  foreach t in array array['night_area','night_ride'] loop
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format(
      'create policy p_%1$s on public.%1$s for all
         using (tenant_id = app.my_tenant() and app.can_store(store_id))
         with check (tenant_id = app.my_tenant() and app.can_store(store_id))', t);
  end loop;
end $$;


-- ----------------------------------------------------------------------------
--  4. 送りを登録する
--     エリアを選ぶと、送り代とドライバー代はエリアの設定から自動で入ります。
-- ----------------------------------------------------------------------------
create or replace function public.night_ride_add(
  p_store       uuid,
  p_subject     text default 'customer',
  p_customer    uuid default null,
  p_cast        uuid default null,
  p_label       text default null,
  p_area        uuid default null,
  p_destination text default null,
  p_head_count  integer default 1,
  p_visit       uuid default null,
  p_note        text default null
) returns public.night_ride
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; st public.store; ar public.night_area;
  r public.night_ride; bd date; nx integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = p_store;
  bd := app.business_date(now(), st.day_cutoff);

  if p_area is not null then
    select * into ar from public.night_area where id = p_area and store_id = p_store;
  end if;

  select coalesce(max(seq),0) + 1 into nx
    from public.night_ride where store_id = p_store and business_date = bd;

  insert into public.night_ride(
    tenant_id, store_id, business_date, subject, customer_id, cast_id, label,
    visit_id, area_id, destination, head_count, fee, driver_fee, seq, note, created_by)
  values (
    me.tenant_id, p_store, bd, p_subject, p_customer, p_cast, p_label,
    p_visit, p_area, p_destination, greatest(p_head_count,1),
    coalesce(ar.fee,0), coalesce(ar.driver_fee,0), nx, p_note, me.id)
  returning * into r;

  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  5. ドライバーを割り当てる／状態を進める
-- ----------------------------------------------------------------------------
create or replace function public.night_ride_assign(p_ride uuid, p_driver uuid)
returns public.night_ride
language plpgsql security definer set search_path = public, app
as $$
declare r public.night_ride;
begin
  select * into r from public.night_ride where id = p_ride;
  if not found then raise exception '送りが見つかりません'; end if;
  if not app.can_store(r.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.night_ride set driver_id = p_driver where id = p_ride returning * into r;
  return r;
end;
$$;

create or replace function public.night_ride_status(p_ride uuid, p_status text)
returns public.night_ride
language plpgsql security definer set search_path = public, app
as $$
declare r public.night_ride; me public.staff;
begin
  select * into me from app.me();
  select * into r from public.night_ride where id = p_ride;
  if not found then raise exception '送りが見つかりません'; end if;
  if not app.can_store(r.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_status not in ('waiting','onboard','done','canceled') then
    raise exception '状態の指定が正しくありません';
  end if;

  update public.night_ride
     set status = p_status,
         departed_at = case when p_status = 'onboard' then coalesce(departed_at, now())
                            when p_status = 'waiting' then null else departed_at end,
         arrived_at  = case when p_status = 'done' then coalesce(arrived_at, now())
                            when p_status in ('waiting','onboard') then null else arrived_at end
   where id = p_ride
   returning * into r;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (r.tenant_id, r.store_id, me.id, 'ride_' || p_status, 'night_ride', r.id::text, '{}'::jsonb);

  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  6. 順番を入れ替える（上へ／下へ）
-- ----------------------------------------------------------------------------
create or replace function public.night_ride_move(p_ride uuid, p_dir integer)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare r public.night_ride; o public.night_ride;
begin
  select * into r from public.night_ride where id = p_ride;
  if not found then return false; end if;
  if not app.can_store(r.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  if p_dir < 0 then
    select * into o from public.night_ride
     where store_id = r.store_id and business_date = r.business_date
       and status in ('waiting','onboard') and seq < r.seq
     order by seq desc limit 1;
  else
    select * into o from public.night_ride
     where store_id = r.store_id and business_date = r.business_date
       and status in ('waiting','onboard') and seq > r.seq
     order by seq asc limit 1;
  end if;

  if not found then return false; end if;

  update public.night_ride set seq = o.seq where id = r.id;
  update public.night_ride set seq = r.seq where id = o.id;
  return true;
end;
$$;


-- ----------------------------------------------------------------------------
--  7. その日の送り一覧
-- ----------------------------------------------------------------------------
create or replace function public.night_ride_day(
  p_store uuid, p_date date default null
) returns table (
  id           uuid,
  seq          integer,
  subject      text,
  who          text,
  area_name    text,
  destination  text,
  head_count   integer,
  fee          integer,
  driver_fee   integer,
  driver_name  text,
  driver_id    uuid,
  status       text,
  requested_at timestamptz,
  departed_at  timestamptz,
  arrived_at   timestamptz,
  note         text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare st public.store; bd date;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  bd := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  return query
  select r.id, r.seq, r.subject,
         coalesce(cu.name, ca.name, r.label, '（名前なし）'),
         ar.name, r.destination, r.head_count, r.fee, r.driver_fee,
         dv.name, r.driver_id, r.status,
         r.requested_at, r.departed_at, r.arrived_at, r.note
    from public.night_ride r
    left join public.night_customer cu on cu.id = r.customer_id
    left join public.night_cast ca     on ca.id = r.cast_id
    left join public.night_area ar     on ar.id = r.area_id
    left join public.staff dv          on dv.id = r.driver_id
   where r.store_id = p_store and r.business_date = bd
   order by
     case r.status when 'onboard' then 0 when 'waiting' then 1
                   when 'done' then 2 else 3 end,
     r.seq;
end;
$$;


-- ----------------------------------------------------------------------------
--  8. 期間の集計（ドライバー別・エリア別）
-- ----------------------------------------------------------------------------
create or replace function public.night_ride_summary(
  p_store uuid, p_from date, p_to date
) returns table (
  kind        text,      -- driver / area
  name        text,
  rides       integer,
  heads       integer,
  fee_total   integer,
  driver_cost integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select 'driver'::text, coalesce(dv.name, '未割当'),
         count(*)::integer, coalesce(sum(r.head_count),0)::integer,
         coalesce(sum(r.fee),0)::integer, coalesce(sum(r.driver_fee),0)::integer
    from public.night_ride r
    left join public.staff dv on dv.id = r.driver_id
   where r.store_id = p_store and r.business_date between p_from and p_to
     and r.status = 'done'
   group by dv.name
  union all
  select 'area'::text, coalesce(ar.name, '未設定'),
         count(*)::integer, coalesce(sum(r.head_count),0)::integer,
         coalesce(sum(r.fee),0)::integer, coalesce(sum(r.driver_fee),0)::integer
    from public.night_ride r
    left join public.night_area ar on ar.id = r.area_id
   where r.store_id = p_store and r.business_date between p_from and p_to
     and r.status = 'done'
   group by ar.name
   order by 1, 5 desc;
end;
$$;


-- ----------------------------------------------------------------------------
--  9. エリアのひな形
-- ----------------------------------------------------------------------------
create or replace function public.night_seed_area(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; n integer;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception 'エリアの初期設定は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  if exists (select 1 from public.night_area where store_id = p_store) then return 0; end if;

  select * into st from public.store where id = p_store;
  insert into public.night_area(tenant_id, store_id, name, fee, driver_fee, sort_order)
  values (st.tenant_id, p_store, '店の近く（徒歩圏）',      0,    500, 10),
         (st.tenant_id, p_store, '市内（近距離）',       1000,   800, 20),
         (st.tenant_id, p_store, '市内（遠距離）',       2000,  1500, 30),
         (st.tenant_id, p_store, '市外',                 3000,  2500, 40);
  get diagnostics n = row_count;
  return n;
end;
$$;


-- ----------------------------------------------------------------------------
--  10. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_ride_add(uuid, text, uuid, uuid, text, uuid, text, integer, uuid, text),
  public.night_ride_assign(uuid, uuid),
  public.night_ride_status(uuid, text),
  public.night_ride_move(uuid, integer),
  public.night_ride_day(uuid, date),
  public.night_ride_summary(uuid, date, date),
  public.night_seed_area(uuid)
to authenticated;


-- ============================================================================
--  デモ用：エリアと、今夜の送り3件
-- ============================================================================
do $$
declare
  t_id uuid; s_id uuid; bd date;
  a_near uuid; a_city uuid; a_far uuid;
  dv uuid; cu uuid; ca uuid;
begin
  select id into s_id from public.store where name = '三宮本店' limit 1;
  if s_id is null then return; end if;
  select tenant_id into t_id from public.store where id = s_id;
  if exists (select 1 from public.night_area where store_id = s_id) then return; end if;

  insert into public.night_area(tenant_id, store_id, name, fee, driver_fee, sort_order)
  values (t_id, s_id, '三宮・元町',    0,    500, 10) returning id into a_near;
  insert into public.night_area(tenant_id, store_id, name, fee, driver_fee, sort_order)
  values (t_id, s_id, '灘・六甲道', 1500,  1000, 20) returning id into a_city;
  insert into public.night_area(tenant_id, store_id, name, fee, driver_fee, sort_order)
  values (t_id, s_id, '西宮・芦屋', 3000,  2000, 30) returning id into a_far;

  -- ドライバー役のスタッフ（いなければ作る）
  select id into dv from public.staff where tenant_id = t_id and role = 'driver' limit 1;
  if dv is null then
    insert into public.staff(tenant_id, name, role) values (t_id, '運転手 山口', 'driver')
    returning id into dv;
    insert into public.staff_store(staff_id, store_id) values (dv, s_id);
  end if;

  select app.business_date(now(), day_cutoff) into bd from public.store where id = s_id;

  select id into cu from public.night_customer where store_id = s_id and name = '伊藤様';
  select id into ca from public.night_cast where store_id = s_id and name = 'れい';

  insert into public.night_ride(tenant_id, store_id, business_date, subject, customer_id,
                                area_id, destination, head_count, fee, driver_fee,
                                driver_id, seq, status)
  values (t_id, s_id, bd, 'customer', cu, a_city, 'ご自宅（六甲道）', 2, 1500, 1000, dv, 1, 'onboard');

  insert into public.night_ride(tenant_id, store_id, business_date, subject, label,
                                area_id, destination, head_count, fee, driver_fee, seq, status)
  values (t_id, s_id, bd, 'customer', '中村様', a_far, '西宮北口', 3, 3000, 2000, 2, 'waiting');

  insert into public.night_ride(tenant_id, store_id, business_date, subject, cast_id,
                                area_id, destination, head_count, fee, driver_fee, seq, status)
  values (t_id, s_id, bd, 'cast', ca, a_near, '自宅（元町）', 1, 0, 500, 3, 'waiting');

  -- 昨日ぶん（集計に出るよう、完了済みで入れておきます）
  insert into public.night_ride(tenant_id, store_id, business_date, subject, label,
                                area_id, destination, head_count, fee, driver_fee,
                                driver_id, seq, status, departed_at, arrived_at)
  values
    (t_id, s_id, bd - 1, 'customer', '佐藤様', a_city, 'ご自宅', 2, 1500, 1000, dv, 1, 'done',
     (bd + time '01:10') at time zone 'Asia/Tokyo', (bd + time '01:35') at time zone 'Asia/Tokyo'),
    (t_id, s_id, bd - 1, 'customer', '渡辺様', a_far, '芦屋川', 2, 3000, 2000, dv, 2, 'done',
     (bd + time '01:40') at time zone 'Asia/Tokyo', (bd + time '02:15') at time zone 'Asia/Tokyo'),
    (t_id, s_id, bd - 1, 'cast', null, a_near, '自宅', 1, 0, 500, dv, 3, 'done',
     (bd + time '02:20') at time zone 'Asia/Tokyo', (bd + time '02:30') at time zone 'Asia/Tokyo');
end $$;
