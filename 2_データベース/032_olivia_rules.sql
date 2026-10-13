-- ============================================================================
--  ナイトだんどり / 会計の端数・打刻の丸め・一律控除・折半（店舗ごとの設定）
--  032_olivia_rules.sql
--
--  貼り付け先： SQL Editor（001 … 031 のあと）。何度流しても壊れません。
--  どれも「店舗の設定」で入れたときだけ効きます。入れていない店舗は、いままでどおりです。
--
--  【店舗の設定（public.store に足す列）】
--    bill_round        会計の合計を、この単位で丸める（1000 → 〇万〇千円。500 円以上は切り上げ、未満は切り下げ）
--    clock_round       打刻を、この分刻みにそろえる（30 → 出勤は次の 30 分へ、退勤は前の 30 分へ）
--    pay_withhold_pct  総支給から、成績に関係なく一律で引く %（10 → 総支給 × 10%）
--    seat_split        卓についたキャストを「指名」として数え、伝票の小計を、ついた人数で均等に分ける
--    table_back_pct    seat_split のとき、卓の商品（ドリンク・同伴など自分のバックが付く明細を除く）の
--                      小計を人数で割ったぶんに付けるバック %（予備バック）
--
--  【給与の試算に足す列】 gross_amount（総支給）/ withhold（一律控除）/ table_back（予備バック）
--    deduction（控除）と net_amount（差引支給）は、一律控除を含めた額になります。
--    （給与の確定・明細は、いままでどおり deduction / net_amount を見ます）
--
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================

alter table public.store add column if not exists bill_round       integer not null default 0;
alter table public.store add column if not exists clock_round      integer not null default 0;
alter table public.store add column if not exists pay_withhold_pct numeric not null default 0;
alter table public.store add column if not exists seat_split       boolean not null default false;
alter table public.store add column if not exists table_back_pct   numeric not null default 0;

-- 伝票：端数の調整額（合計 − 丸める前の合計）。画面に「端数調整」として出します
alter table public.night_visit add column if not exists round_adj integer not null default 0;


-- ----------------------------------------------------------------------------
--  1. 会計の合計を丸める（bill_round）
-- ----------------------------------------------------------------------------
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
  v_raw integer := 0;
  v_total integer := 0;
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

  v_raw := greatest(v_sub + v_svc + v_tax - v.discount, 0);
  v_total := v_raw;
  -- 〇万〇千円にそろえる：単位の半分以上は切り上げ、未満は切り下げ（例：12,500 → 13,000 / 12,499 → 12,000）
  if coalesce(st.bill_round, 0) > 0 then
    v_total := (floor((v_raw + st.bill_round / 2.0) / st.bill_round) * st.bill_round)::integer;
  end if;

  update public.night_visit
     set subtotal = v_sub,
         service_charge = v_svc,
         tax = v_tax,
         total = v_total,
         round_adj = v_total - v_raw
   where id = p_visit
   returning * into v;

  return v;
end;
$$;

-- まだ開いている伝票は、設定に合わせて計算し直す（締めた伝票は触りません）
do $$
declare r record;
begin
  for r in select v.id from public.night_visit v join public.store s on s.id = v.store_id
            where v.status = 'open' and s.bill_round > 0 loop
    perform public.night_recalc_visit(r.id);
  end loop;
end $$;


-- ----------------------------------------------------------------------------
--  2. 打刻を clock_round 分刻みにそろえる（出勤は次へ、退勤は前へ。秒は見ません）
-- ----------------------------------------------------------------------------
create or replace function app.clock_snap(p_at timestamptz, p_min integer, p_up boolean)
returns timestamptz
language sql immutable
as $$
  select case when coalesce(p_min, 0) <= 0 then p_at
              when p_up then to_timestamp(ceil(extract(epoch from date_trunc('minute', p_at)) / (p_min * 60)) * (p_min * 60))
              else           to_timestamp(floor(extract(epoch from date_trunc('minute', p_at)) / (p_min * 60)) * (p_min * 60))
         end;
$$;

create or replace function public.night_clock_in(
  p_cast uuid,
  p_at   timestamptz default now()
) returns public.night_attendance
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; st public.store; a public.night_attendance; bd date; t timestamptz;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = c.store_id;
  bd := app.business_date(p_at, st.day_cutoff);            -- 営業日は、押した時刻で決めます
  t  := app.clock_snap(p_at, st.clock_round, true);         -- 21:10 → 21:30 / 21:32 → 22:00

  insert into public.night_attendance(tenant_id, store_id, cast_id, business_date, clock_in)
  values (c.tenant_id, c.store_id, c.id, bd, t)
  on conflict (cast_id, business_date) do update set clock_in = excluded.clock_in
  returning * into a;

  return a;
end;
$$;

create or replace function public.night_clock_out(
  p_cast uuid,
  p_at   timestamptz default now()
) returns public.night_attendance
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; st public.store; a public.night_attendance; bd date; t timestamptz;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = c.store_id;
  bd := app.business_date(p_at, st.day_cutoff);
  t  := app.clock_snap(p_at, st.clock_round, false);        -- 01:50 → 01:30

  select * into a from public.night_attendance where cast_id = p_cast and business_date = bd;
  if not found then
    raise exception '出勤の記録がありません。先に出勤を押してください';
  end if;
  if a.clock_in is not null and p_at < a.clock_in and st.clock_round = 0 then
    raise exception '退勤時刻が出勤時刻より前になっています';
  end if;
  -- 丸めで出勤より前になったら（21:40 出勤 → 21:50 退勤 など）、勤務 0 分として出勤と同じ時刻にします
  if a.clock_in is not null and t < a.clock_in then t := a.clock_in; end if;

  update public.night_attendance set clock_out = t
   where id = a.id
   returning * into a;

  return a;
end;
$$;

grant execute on function public.night_clock_in(uuid, timestamptz)  to authenticated;
grant execute on function public.night_clock_out(uuid, timestamptz) to authenticated;


-- ----------------------------------------------------------------------------
--  3. 折半（seat_split）：締めた伝票ごとに、小計をついた人数で割ったぶん
--     sales      … 個人売上（達成率に使う）＝ 小計 ÷ 人数
--     table_base … 予備バックの元 ＝（小計 − ドリンク・同伴・指名の明細）÷ 人数
-- ----------------------------------------------------------------------------
create or replace function app.seat_shares(p_store uuid, p_from date, p_to date)
returns table (cast_id uuid, business_date date, visit_id uuid, sales numeric, table_base numeric)
language sql stable security definer set search_path = public, app
as $$
  with n as (
    select vc.visit_id, count(*)::numeric as people
      from public.night_visit_cast vc
      join public.night_visit v on v.id = vc.visit_id
     where v.store_id = p_store and v.status = 'closed'
       and v.business_date between p_from and p_to
     group by vc.visit_id
  ),
  own as (
    select i.visit_id, coalesce(sum(i.amount), 0) as amt
      from public.night_visit_item i
      join n on n.visit_id = i.visit_id
     where i.category in ('drink', 'douhan', 'nomination')
     group by i.visit_id
  )
  select vc.cast_id, v.business_date, v.id,
         v.subtotal / n.people,
         greatest(v.subtotal - coalesce(own.amt, 0), 0) / n.people
    from public.night_visit_cast vc
    join n on n.visit_id = vc.visit_id
    join public.night_visit v on v.id = vc.visit_id
    left join own on own.visit_id = vc.visit_id;
$$;


-- ----------------------------------------------------------------------------
--  4. 給与の試算（列が増えるので、いったん消して作り直します）
-- ----------------------------------------------------------------------------
drop function if exists public.night_payroll_preview(uuid, date, date);
drop function if exists app.night_payroll_preview_nolid(uuid, date, date);

create function public.night_payroll_preview(
  p_store uuid, p_from date, p_to date
) returns table (
  cast_id        uuid,
  cast_name      text,
  work_minutes   integer,
  work_days      integer,
  late_minutes   integer,
  nominations    integer,
  douhans        integer,
  drinks         integer,
  sales          integer,
  hourly_base    integer,
  hourly_applied integer,
  wage_amount    integer,
  back_amount    integer,
  allowance      integer,
  deduction      integer,     -- 控除（一律控除を含む）
  advance        integer,
  net_amount     integer,     -- 差引支給（総支給 − 控除 − 日払い）
  below_min_wage boolean,
  confirmed      boolean,
  achieved_pct   integer,     -- 達成率（%）
  back_bonus     integer,     -- バックのうち、達成で上がったぶん
  gross_amount   integer,     -- 総支給（時給ぶん＋バック＋手当）
  withhold       integer,     -- 一律控除（総支給 × pay_withhold_pct）
  table_back     integer      -- バックのうち、予備バック（折半の店舗だけ）
)
language plpgsql stable security definer set search_path = public, app
as $$
declare st public.store; v_split boolean;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p_store;
  v_split := coalesce(st.seat_split, false);

  return query
  with att as (
    select a.cast_id,
           coalesce(sum(
             case when a.clock_in is not null and a.clock_out is not null
                  then greatest(extract(epoch from (a.clock_out - a.clock_in))::integer / 60, 0)
                  else 0 end), 0)::integer as minutes,
           count(*) filter (where a.clock_in is not null)::integer as days,
           coalesce(sum(a.late_minutes),0)::integer as late
      from public.night_attendance a
     where a.store_id = p_store and a.business_date between p_from and p_to
     group by a.cast_id
  ),
  perf as (
    -- 明細ごとのバック。折半の店舗では、ドリンク・同伴・指名のバックだけ（卓の商品は予備バックで払う）
    select i.cast_id,
           count(*) filter (where i.category = 'nomination')::integer as noms,
           count(*) filter (where i.category = 'douhan')::integer     as dous,
           count(*) filter (where i.category = 'drink')::integer      as drks,
           coalesce(sum(i.amount),0)::integer      as sales,
           coalesce(sum(i.back_amount) filter (
             where not v_split or i.category in ('drink','douhan','nomination')),0)::integer as back
      from public.night_visit_item i
      join public.night_visit v on v.id = i.visit_id
     where i.store_id = p_store and v.status = 'closed'
       and v.business_date between p_from and p_to
       and i.cast_id is not null
     group by i.cast_id
  ),
  seat as (
    select s.cast_id,
           count(distinct s.visit_id)::integer as noms,
           coalesce(sum(s.sales), 0)           as sales,
           coalesce(sum(s.table_base), 0)      as tbase
      from app.seat_shares(p_store, p_from, p_to) s
     where v_split
     group by s.cast_id
  ),
  adj as (
    select j.cast_id,
           coalesce(sum(j.amount) filter (where j.kind = 'allowance'),0)::integer as allw,
           coalesce(sum(j.amount) filter (where j.kind = 'deduction'),0)::integer as dedu
      from public.night_adjustment j
     where j.store_id = p_store and j.business_date between p_from and p_to
     group by j.cast_id
  ),
  pay as (
    select o.cast_id, coalesce(sum(o.amount),0)::integer as adv
      from public.night_payout o
     where o.store_id = p_store and o.business_date between p_from and p_to
     group by o.cast_id
  ),
  base as (
    select c.id, c.name, c.hourly_wage,
           coalesce(a.minutes,0) as minutes,
           coalesce(a.days,0)    as days,
           coalesce(a.late,0)    as late,
           case when v_split then coalesce(s.noms,0) + coalesce(p.noms,0) else coalesce(p.noms,0) end as noms,
           coalesce(p.dous,0)    as dous,
           coalesce(p.drks,0)    as drks,
           case when v_split then round(coalesce(s.sales,0))::integer else coalesce(p.sales,0) end as sales,
           coalesce(s.tbase,0)   as tbase,
           coalesce(p.back,0)    as back,
           coalesce(j.allw,0)    as allw,
           coalesce(j.dedu,0)    as dedu,
           coalesce(y.adv,0)     as adv
      from public.night_cast c
      left join att  a on a.cast_id = c.id
      left join perf p on p.cast_id = c.id
      left join seat s on s.cast_id = c.id
      left join adj  j on j.cast_id = c.id
      left join pay  y on y.cast_id = c.id
     where c.store_id = p_store
       and (c.is_active or a.cast_id is not null or p.cast_id is not null or s.cast_id is not null)
  ),
  calc as (
    select b.*,
           app.wage_for(b.id, b.noms, b.sales, b.minutes)       as hourly,
           app.achieved_pct(b.id, b.sales, b.minutes)           as pct,
           app.back_floor_for(b.id, b.noms, b.sales, b.minutes) as fl
      from base b
  ),
  bonus as (
    select c.id,
           case when c.fl > 0 then
             coalesce((select sum(app.back_with_floor(i.back_amount, i.amount, c.fl) - i.back_amount)
                         from public.night_visit_item i
                         join public.night_visit v on v.id = i.visit_id
                        where i.cast_id = c.id and v.status = 'closed'
                          and v.business_date between p_from and p_to
                          and (not v_split or i.category in ('drink','douhan','nomination'))), 0)
           else 0 end::integer as bns,
           -- 予備バック：卓の商品の取り分 × 率（達成でバック率が上がっていれば、その率）
           case when v_split and coalesce(st.table_back_pct, 0) > 0
                then floor(c.tbase * greatest(st.table_back_pct, c.fl) / 100.0)::integer
                else 0 end as tbk,
           case when v_split and coalesce(st.table_back_pct, 0) > 0 and c.fl > st.table_back_pct
                then (floor(c.tbase * c.fl / 100.0) - floor(c.tbase * st.table_back_pct / 100.0))::integer
                else 0 end as tbns
      from calc c
  ),
  money as (
    select c.*, b.bns, b.tbk, b.tbns,
           (round(c.minutes / 60.0 * c.hourly))::integer as wage,
           ((round(c.minutes / 60.0 * c.hourly))::integer + c.back + b.bns + b.tbk + c.allw)::integer as gross
      from calc c
      join bonus b on b.id = c.id
  )
  select m.id, m.name, m.minutes, m.days, m.late,
         m.noms, m.dous, m.drks, m.sales,
         m.hourly_wage,
         m.hourly,
         m.wage,
         (m.back + m.bns + m.tbk)::integer,
         m.allw,
         (m.dedu + round(m.gross * coalesce(st.pay_withhold_pct, 0) / 100.0))::integer,
         m.adv,
         (m.gross - m.dedu - round(m.gross * coalesce(st.pay_withhold_pct, 0) / 100.0) - m.adv)::integer,
         (st.min_wage > 0 and m.hourly < st.min_wage),
         exists (select 1 from public.night_payroll pr
                  where pr.cast_id = m.id and pr.period_from = p_from and pr.period_to = p_to),
         m.pct,
         (m.bns + m.tbns)::integer,
         m.gross,
         round(m.gross * coalesce(st.pay_withhold_pct, 0) / 100.0)::integer,
         m.tbk
    from money m
   order by m.name;
end;
$$;

grant execute on function public.night_payroll_preview(uuid, date, date) to authenticated;
grant execute on function app.seat_shares(uuid, date, date) to authenticated;


-- ----------------------------------------------------------------------------
--  5. 日ごとの内訳も、同じ考え方で（折半・予備バック・指名＝ついた卓の数）
-- ----------------------------------------------------------------------------
drop function if exists app.night_payroll_daily_nolid(uuid, date, date);

create or replace function public.night_payroll_daily(
  p_cast uuid, p_from date, p_to date
)
returns table (
  business_date date,
  weekday       text,
  clock_in_hm   text,
  clock_out_hm  text,
  work_minutes  integer,
  work_hours    numeric,
  late_minutes  integer,
  hourly        integer,
  wage_amount   integer,
  nominations   integer,
  douhans       integer,
  drinks        integer,
  sales         integer,
  back_amount   integer,
  payout        integer,
  allowance     integer,
  deduction     integer,
  note          text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare c public.night_cast; st public.store; v_split boolean;
        v_hourly integer; v_noms integer; v_sales integer; v_minutes integer; v_floor numeric; v_trate numeric;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = c.store_id;
  v_split := coalesce(st.seat_split, false);

  -- 期間ぜんぶの指名本数・個人売上・勤務時間から、適用される時給とバック率を決めます
  if v_split then
    select count(distinct s.visit_id)::integer, round(coalesce(sum(s.sales), 0))::integer
      into v_noms, v_sales
      from app.seat_shares(c.store_id, p_from, p_to) s where s.cast_id = p_cast;
  else
    select count(*) filter (where i.category = 'nomination')::integer,
           coalesce(sum(i.amount), 0)::integer
      into v_noms, v_sales
      from public.night_visit_item i
      join public.night_visit v on v.id = i.visit_id
     where i.cast_id = p_cast and v.status = 'closed'
       and v.business_date between p_from and p_to;
  end if;

  select coalesce(sum(
           case when a.clock_in is not null and a.clock_out is not null
                then greatest(extract(epoch from (a.clock_out - a.clock_in))::integer / 60, 0)
                else 0 end), 0)::integer
    into v_minutes
    from public.night_attendance a
   where a.cast_id = p_cast and a.business_date between p_from and p_to;

  v_hourly := app.wage_for(p_cast, coalesce(v_noms, 0), coalesce(v_sales, 0), v_minutes);
  v_floor  := app.back_floor_for(p_cast, coalesce(v_noms, 0), coalesce(v_sales, 0), v_minutes);
  v_trate  := case when v_split and coalesce(st.table_back_pct, 0) > 0
                   then greatest(st.table_back_pct, v_floor) else 0 end;

  return query
  with days as (
    select d::date as bd
      from generate_series(p_from, p_to, interval '1 day') d
  ),
  att as (
    select a.business_date as bd,
           a.clock_in, a.clock_out, a.late_minutes, a.note,
           case when a.clock_in is not null and a.clock_out is not null
                then greatest(extract(epoch from (a.clock_out - a.clock_in))::integer / 60, 0)
                else 0 end as mins
      from public.night_attendance a
     where a.cast_id = p_cast and a.business_date between p_from and p_to
  ),
  perf as (
    select v.business_date as bd,
           count(*) filter (where i.category = 'nomination')::integer as noms,
           count(*) filter (where i.category = 'douhan')::integer     as dous,
           count(*) filter (where i.category = 'drink')::integer      as drks,
           coalesce(sum(i.amount), 0)::integer      as sales,
           coalesce(sum(app.back_with_floor(i.back_amount, i.amount, v_floor)) filter (
             where not v_split or i.category in ('drink','douhan','nomination')), 0)::integer as back
      from public.night_visit_item i
      join public.night_visit v on v.id = i.visit_id
     where i.cast_id = p_cast and v.status = 'closed'
       and v.business_date between p_from and p_to
     group by v.business_date
  ),
  seat as (
    select s.business_date as bd,
           count(distinct s.visit_id)::integer as noms,
           coalesce(sum(s.sales), 0) as sales,
           coalesce(sum(s.table_base), 0) as tbase
      from app.seat_shares(c.store_id, p_from, p_to) s
     where v_split and s.cast_id = p_cast
     group by s.business_date
  ),
  pay as (
    select o.business_date as bd, coalesce(sum(o.amount), 0)::integer as adv
      from public.night_payout o
     where o.cast_id = p_cast and o.business_date between p_from and p_to
     group by o.business_date
  ),
  adj as (
    select j.business_date as bd,
           coalesce(sum(j.amount) filter (where j.kind = 'allowance'), 0)::integer as allw,
           coalesce(sum(j.amount) filter (where j.kind = 'deduction'), 0)::integer as dedu
      from public.night_adjustment j
     where j.cast_id = p_cast and j.business_date between p_from and p_to
     group by j.business_date
  )
  select
    d.bd,
    case extract(dow from d.bd)::integer
      when 0 then '日' when 1 then '月' when 2 then '火' when 3 then '水'
      when 4 then '木' when 5 then '金' else '土' end,
    to_char(a.clock_in  at time zone 'Asia/Tokyo', 'HH24:MI'),
    to_char(a.clock_out at time zone 'Asia/Tokyo', 'HH24:MI'),
    coalesce(a.mins, 0),
    round(coalesce(a.mins, 0)::numeric / 60, 2),
    coalesce(a.late_minutes, 0),
    v_hourly,
    (round(coalesce(a.mins, 0) / 60.0 * v_hourly))::integer,
    case when v_split then coalesce(s.noms, 0) + coalesce(p.noms, 0) else coalesce(p.noms, 0) end,
    coalesce(p.dous, 0), coalesce(p.drks, 0),
    case when v_split then round(coalesce(s.sales, 0))::integer else coalesce(p.sales, 0) end,
    (coalesce(p.back, 0) + floor(coalesce(s.tbase, 0) * v_trate / 100.0))::integer,
    coalesce(y.adv, 0),
    coalesce(j.allw, 0), coalesce(j.dedu, 0),
    a.note
  from days d
  left join att  a on a.bd = d.bd
  left join perf p on p.bd = d.bd
  left join seat s on s.bd = d.bd
  left join pay  y on y.bd = d.bd
  left join adj  j on j.bd = d.bd
  where a.bd is not null or p.bd is not null or s.bd is not null or y.bd is not null or j.bd is not null
  order by d.bd;
end;
$$;

grant execute on function public.night_payroll_daily(uuid, date, date) to authenticated;


-- ----------------------------------------------------------------------------
--  6. シフトの一覧（だれが・どの日に・何時から）＋ 実際の出勤
-- ----------------------------------------------------------------------------
create or replace function public.wish_grid(p_period uuid)
returns table (
  subject_kind text, subject_id uuid, name text, status text, status_label text,
  days jsonb      -- { "2026-10-01": {"kind":"ok","from":"21:00","to":"02:00","in":"21:30","out":"01:30"}, … }
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare p public.shift_period;
begin
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select pe.subject_kind, pe.subject_id, pe.name,
         coalesce(w.status, 'draft'),
         case coalesce(w.status, 'draft')
           when 'draft' then 'まだ' when 'submitted' then '提出' when 'approved' then '確定'
           when 'returned' then '差し戻し' else w.status end,
         coalesce((
           select jsonb_object_agg(x.bd::text, x.j)
             from (
               select coalesce(wd.business_date, at.business_date) as bd,
                      jsonb_strip_nulls(jsonb_build_object(
                        'kind', wd.kind,
                        'from', to_char(coalesce(wd.from_time, sl.start_time), 'HH24:MI'),
                        'to',   to_char(coalesce(wd.to_time,   sl.end_time),   'HH24:MI'),
                        'in',   to_char(at.clock_in  at time zone 'Asia/Tokyo', 'HH24:MI'),
                        'out',  to_char(at.clock_out at time zone 'Asia/Tokyo', 'HH24:MI'))) as j
                 from (select d.* from public.shift_wish_day d where d.wish_id = w.id) wd
                 left join public.shift_slot sl on sl.id = wd.slot_id
                 full join (select a.* from public.night_attendance a
                             where pe.subject_kind = 'night_cast' and a.cast_id = pe.subject_id
                               and a.business_date between p.period_from and p.period_to) at
                   on at.business_date = wd.business_date
             ) x
            where x.bd is not null
         ), '{}'::jsonb)
    from public.shift_people(p.store_id) pe
    left join public.shift_wish w
      on w.period_id = p_period and w.subject_kind = pe.subject_kind and w.subject_id = pe.subject_id
   order by pe.name;
end;
$$;

grant execute on function public.wish_grid(uuid) to authenticated;


-- ----------------------------------------------------------------------------
--  7. 017-027 の「ふた」（店長以上だけ・本人だけ）を付け直す
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('app.add_guard(text,text,text)') is not null then
    raise notice '%', app.add_guard('public.night_payroll_preview(uuid,date,date)', 'boss', '給与の計算');
    raise notice '%', app.add_guard('public.night_payroll_daily(uuid,date,date)',   'mine', '給与の内訳');
  end if;
end $$;

notify pgrst, 'reload schema';
