-- ============================================================================
--  ナイトだんどり / 顧客・LINE集客パック
--  009_customer.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜006 を先に実行しておいてください）
--
--  お客様の台帳、来店周期からの声かけリスト、連絡の履歴です。
--  何度実行しても壊れません。
--
--  ※ LINEでの一斉配信そのものは、店舗さまのLINE公式アカウントが必要です。
--    このパックは「誰に声をかけるか」を出すところまでを担当し、
--    送信は公式アカウントの管理画面から行う前提にしています。
--    連絡先の書き出し（CSV）に対応しています。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. お客様の台帳に項目を足す
-- ----------------------------------------------------------------------------
alter table public.night_customer
  add column if not exists birthday      date,
  add column if not exists likes         text,      -- お好み（お酒・話題）
  add column if not exists dislikes      text,      -- 避けたい話題・NG
  add column if not exists intro_by      text,      -- ご紹介者
  add column if not exists contact_pref  text default 'line',  -- line / tel / none
  add column if not exists line_ok       boolean not null default true,
  add column if not exists block_reason  text;

comment on column public.night_customer.contact_pref is
  'ご連絡の手段。none はご本人からのご希望で連絡しない方';
comment on column public.night_customer.line_ok is
  'LINEでのご案内に同意いただけているか。false の方は配信リストに出ません';


-- ----------------------------------------------------------------------------
--  2. 連絡の履歴
-- ----------------------------------------------------------------------------
create table if not exists public.night_contact_log (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant(id) on delete cascade,
  store_id     uuid not null references public.store(id) on delete cascade,
  customer_id  uuid not null references public.night_customer(id) on delete cascade,
  contacted_on date not null default current_date,
  kind         text not null,          -- line / tel / mail / visit / other
  result       text not null default 'sent',  -- sent / replied / booked / declined / no_answer
  cast_id      uuid references public.night_cast(id) on delete set null,
  memo         text,
  created_by   uuid references public.staff(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_contact_cust on public.night_contact_log(customer_id, contacted_on desc);
create index if not exists idx_contact_store on public.night_contact_log(store_id, contacted_on desc);

alter table public.night_contact_log enable row level security;
drop policy if exists p_night_contact_log on public.night_contact_log;
create policy p_night_contact_log on public.night_contact_log for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id));


-- ----------------------------------------------------------------------------
--  3. 連絡を記録する
-- ----------------------------------------------------------------------------
create or replace function public.night_contact_add(
  p_customer uuid,
  p_kind     text,
  p_result   text default 'sent',
  p_memo     text default null,
  p_cast     uuid default null,
  p_on       date default current_date
) returns public.night_contact_log
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; cu public.night_customer; r public.night_contact_log;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into cu from public.night_customer where id = p_customer;
  if not found then raise exception 'お客様が見つかりません'; end if;
  if not app.can_store(cu.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  insert into public.night_contact_log(
    tenant_id, store_id, customer_id, contacted_on, kind, result, cast_id, memo, created_by)
  values (cu.tenant_id, cu.store_id, cu.id, p_on, p_kind, p_result, p_cast, p_memo, me.id)
  returning * into r;

  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  4. そろそろの方リスト
--
--     来店の間隔から「いつもならもう来ている頃」の方を出します。
--     2回以上ご来店の方は、その方自身の平均間隔を基準にします。
--     1回だけの方は、p_first_days 日を過ぎたら出します。
-- ----------------------------------------------------------------------------
create or replace function public.night_customer_due(
  p_store       uuid,
  p_over_rate   numeric default 1.2,   -- 平均間隔の何倍を過ぎたら出すか
  p_first_days  integer default 45,    -- 1回だけの方は何日で出すか
  p_limit       integer default 50
) returns table (
  customer_id     uuid,
  name            text,
  main_cast       text,
  visits          integer,
  last_visit      date,
  days_since      integer,
  avg_interval    integer,
  over_days       integer,
  total_sales     integer,
  per_visit       integer,
  last_contact_on date,
  contact_pref    text,
  line_ok         boolean
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  with v as (
    select customer_id, business_date, total
      from public.night_visit
     where store_id = p_store and status = 'closed' and customer_id is not null
  ),
  agg as (
    select customer_id,
           count(*)::integer                     as visits,
           max(business_date)                    as last_visit,
           min(business_date)                    as first_visit,
           coalesce(sum(total),0)::integer       as total_sales,
           case when count(*) > 1
                then ((max(business_date) - min(business_date))::numeric / (count(*) - 1))
                else null end                    as avg_gap
      from v group by customer_id
  ),
  lc as (
    select customer_id, max(contacted_on) as last_contact_on
      from public.night_contact_log where store_id = p_store group by customer_id
  )
  select c.id, c.name, ca.name,
         a.visits, a.last_visit,
         (current_date - a.last_visit)::integer,
         coalesce(round(a.avg_gap)::integer, 0),
         case when a.avg_gap is not null
              then ((current_date - a.last_visit) - round(a.avg_gap))::integer
              else ((current_date - a.last_visit) - p_first_days)::integer end,
         a.total_sales,
         (a.total_sales / greatest(a.visits,1))::integer,
         lc.last_contact_on, c.contact_pref, c.line_ok
    from agg a
    join public.night_customer c on c.id = a.customer_id
    left join public.night_cast ca on ca.id = c.main_cast_id
    left join lc on lc.customer_id = a.customer_id
   where c.is_blocked = false
     and c.contact_pref <> 'none'
     and (
       (a.avg_gap is not null and (current_date - a.last_visit) > a.avg_gap * p_over_rate)
       or (a.avg_gap is null and (current_date - a.last_visit) > p_first_days)
     )
   order by 8 desc
   limit greatest(p_limit, 1);
end;
$$;


-- ----------------------------------------------------------------------------
--  5. お誕生日リスト
-- ----------------------------------------------------------------------------
create or replace function public.night_customer_birthday(
  p_store uuid, p_days integer default 30
) returns table (
  customer_id  uuid,
  name         text,
  birthday     date,
  days_until   integer,
  visits       integer,
  last_visit   date,
  main_cast    text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select c.id, c.name, c.birthday,
         -- 今年の誕生日まで（過ぎていれば来年ぶん）
         (case
            when (make_date(extract(year from current_date)::integer,
                            extract(month from c.birthday)::integer,
                            extract(day from c.birthday)::integer) >= current_date)
            then make_date(extract(year from current_date)::integer,
                           extract(month from c.birthday)::integer,
                           extract(day from c.birthday)::integer)
            else make_date(extract(year from current_date)::integer + 1,
                           extract(month from c.birthday)::integer,
                           extract(day from c.birthday)::integer)
          end - current_date)::integer,
         c.visit_count, c.last_visit_on, ca.name
    from public.night_customer c
    left join public.night_cast ca on ca.id = c.main_cast_id
   where c.store_id = p_store
     and c.birthday is not null
     and c.is_blocked = false
   order by 4
   limit 100;
end;
$$;


-- ----------------------------------------------------------------------------
--  6. お客様1人の詳細（来店履歴つき）
-- ----------------------------------------------------------------------------
create or replace function public.night_customer_history(
  p_customer uuid, p_limit integer default 20
) returns table (
  business_date date,
  table_no      text,
  head_count    integer,
  main_cast     text,
  total         integer,
  paid_credit   integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare cu public.night_customer;
begin
  select * into cu from public.night_customer where id = p_customer;
  if not found then raise exception 'お客様が見つかりません'; end if;
  if not app.can_store(cu.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select v.business_date, v.table_no, v.head_count, ca.name, v.total, v.paid_credit
    from public.night_visit v
    left join public.night_cast ca on ca.id = v.main_cast_id
   where v.customer_id = p_customer and v.status = 'closed'
   order by v.business_date desc
   limit greatest(p_limit, 1);
end;
$$;


-- ----------------------------------------------------------------------------
--  7. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_contact_add(uuid, text, text, text, uuid, date),
  public.night_customer_due(uuid, numeric, integer, integer),
  public.night_customer_birthday(uuid, integer),
  public.night_customer_history(uuid, integer)
to authenticated;


-- ============================================================================
--  デモ用：誕生日とお好みを入れておきます
-- ============================================================================
do $$
declare s uuid;
begin
  select id into s from public.store where name = '三宮本店' limit 1;
  if s is null then return; end if;

  update public.night_customer set
    birthday = make_date(1975, extract(month from current_date + 12)::integer,
                         least(extract(day from current_date + 12)::integer, 28)),
    likes = '芋焼酎（お湯割り）／野球の話',
    contact_pref = 'line'
  where store_id = s and name = '佐藤様' and birthday is null;

  update public.night_customer set
    birthday = make_date(1982, 4, 3),
    likes = 'ハイボール／ゴルフ',
    contact_pref = 'tel'
  where store_id = s and name = '田中様' and birthday is null;

  update public.night_customer set
    likes = 'ボトルキープ（ウイスキー）',
    contact_pref = 'line'
  where store_id = s and name = '伊藤様' and likes is null;
end $$;


-- ----------------------------------------------------------------------------
--  デモ用：しばらく来ていないお客様を作る（声かけリストに出る人）
-- ----------------------------------------------------------------------------
do $$
declare
  t_id uuid; s_id uuid; c_aya uuid; c_min uuid;
  cu1 uuid; cu2 uuid; v_id uuid; i integer; d date;
begin
  select id into s_id from public.store where name = '三宮本店' limit 1;
  if s_id is null then return; end if;
  select tenant_id into t_id from public.store where id = s_id;
  if exists (select 1 from public.night_customer where store_id = s_id and name = '高橋様') then
    return;
  end if;
  select id into c_aya from public.night_cast where store_id = s_id and name = 'あや';
  select id into c_min from public.night_cast where store_id = s_id and name = 'みなみ';

  -- 高橋様：14日おきに5回、最後は55日前（いつもならとっくに来ている頃）
  insert into public.night_customer(tenant_id, store_id, name, company, main_cast_id,
                                    likes, contact_pref, first_visit_on, last_visit_on, visit_count)
  values (t_id, s_id, '高橋様', '高橋工務店', c_aya,
          '芋焼酎／競馬の話', 'line', current_date - 111, current_date - 55, 5)
  returning id into cu1;

  for i in 0..4 loop
    d := current_date - 111 + (i * 14);
    insert into public.night_visit(
      tenant_id, store_id, business_date, table_no, customer_id, head_count,
      main_cast_id, entered_at, left_at, status, subtotal, service_charge, tax, total,
      paid_cash, closed_at)
    values (t_id, s_id, d, 'B-2', cu1, 2, c_aya,
            (d + time '21:00') at time zone 'Asia/Tokyo',
            (d + time '23:00') at time zone 'Asia/Tokyo',
            'closed', 30000, 6000, 3600, 39600, 39600,
            (d + time '23:10') at time zone 'Asia/Tokyo')
    returning id into v_id;
  end loop;

  -- 木村様：1度だけ、70日前
  insert into public.night_customer(tenant_id, store_id, name, main_cast_id,
                                    contact_pref, first_visit_on, last_visit_on, visit_count)
  values (t_id, s_id, '木村様', c_min, 'tel', current_date - 70, current_date - 70, 1)
  returning id into cu2;

  d := current_date - 70;
  insert into public.night_visit(
    tenant_id, store_id, business_date, table_no, customer_id, head_count,
    main_cast_id, entered_at, left_at, status, subtotal, service_charge, tax, total,
    paid_card, closed_at)
  values (t_id, s_id, d, 'C-1', cu2, 3, c_min,
          (d + time '20:30') at time zone 'Asia/Tokyo',
          (d + time '22:40') at time zone 'Asia/Tokyo',
          'closed', 42000, 8400, 5040, 55440, 55440,
          (d + time '22:50') at time zone 'Asia/Tokyo');

  -- 高橋様には1度だけ声をかけた履歴を残す
  insert into public.night_contact_log(tenant_id, store_id, customer_id, contacted_on,
                                       kind, result, cast_id, memo)
  values (t_id, s_id, cu1, current_date - 20, 'line', 'no_answer', c_aya, '既読つかず');
end $$;
