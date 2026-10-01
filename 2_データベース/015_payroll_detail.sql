-- ============================================================================
--  だんどりシリーズ 共通 / 給与の内訳（日ごと・1件ごと）
--  015_payroll_detail.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001 → 004 → 013 を先に実行しておいてください）
--
--  「何日に何時間働いたか」「いつの指名で、指名料がいくらか」を
--  1件ずつたどれるようにします。
--
--   ・night_payroll_daily        … 日ごとの出勤・売上・バック
--   ・night_payroll_items        … 指名・同伴・ドリンクを1件ずつ
--   ・night_payroll_item_summary … 種類ごとの合計
--   ・payslip_detail             … 明細に添える内訳（印刷用にひとまとめ）
--
--  どれも、そのつど元の記録から数え直します。
--  伝票や出勤をあとから直せば、この内訳もいっしょに直ります。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ----------------------------------------------------------------------------
--  0. 種類の呼び名
-- ----------------------------------------------------------------------------
create or replace function app.item_label(p_category text)
returns text language sql immutable as $$
  select case p_category
    when 'nomination' then '指名'
    when 'douhan'     then '同伴'
    when 'drink'      then 'ドリンク'
    when 'bottle'     then 'ボトル'
    when 'set'        then 'セット'
    when 'extension'  then '延長'
    when 'food'       then 'フード'
    else 'その他' end;
$$;


-- ----------------------------------------------------------------------------
--  1. 日ごとの内訳
--
--     何日に何時間働き、その日にいくら付いたか。
--     時給は、期間ぜんぶで決まる「適用時給」を各日に当てています
--     （時給スライドが期間の合計で決まるため、日ごとに違う時給は出しません）。
-- ----------------------------------------------------------------------------
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
declare c public.night_cast; v_hourly integer; v_noms integer; v_sales integer;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  -- 期間ぜんぶの本指名本数・売上から、適用される時給を決めます
  select count(*) filter (where i.category = 'nomination')::integer,
         coalesce(sum(i.amount), 0)::integer
    into v_noms, v_sales
    from public.night_visit_item i
    join public.night_visit v on v.id = i.visit_id
   where i.cast_id = p_cast and v.status = 'closed'
     and v.business_date between p_from and p_to;

  v_hourly := app.wage_for(p_cast, coalesce(v_noms, 0), coalesce(v_sales, 0));

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
           coalesce(sum(i.back_amount), 0)::integer as back
      from public.night_visit_item i
      join public.night_visit v on v.id = i.visit_id
     where i.cast_id = p_cast and v.status = 'closed'
       and v.business_date between p_from and p_to
     group by v.business_date
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
    coalesce(p.noms, 0), coalesce(p.dous, 0), coalesce(p.drks, 0),
    coalesce(p.sales, 0), coalesce(p.back, 0),
    coalesce(y.adv, 0),
    coalesce(j.allw, 0), coalesce(j.dedu, 0),
    a.note
  from days d
  left join att  a on a.bd = d.bd
  left join perf p on p.bd = d.bd
  left join pay  y on y.bd = d.bd
  left join adj  j on j.bd = d.bd
  where a.bd is not null or p.bd is not null or y.bd is not null or j.bd is not null
  order by d.bd;
end;
$$;


-- ----------------------------------------------------------------------------
--  2. 1件ずつの内訳
--
--     いつ・どの卓で・何が付いて・いくらだったか。
--     p_category に 'nomination' を渡せば、指名だけを並べられます。
-- ----------------------------------------------------------------------------
create or replace function public.night_payroll_items(
  p_cast uuid, p_from date, p_to date, p_category text default null
)
returns table (
  business_date date,
  punched_hm    text,
  table_no      text,
  category      text,
  category_name text,
  name          text,
  quantity      integer,
  unit_price    integer,
  amount        integer,
  back_amount   integer,
  customer_name text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare c public.night_cast;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select v.business_date,
         to_char(i.punched_at at time zone 'Asia/Tokyo', 'HH24:MI'),
         v.table_no,
         i.category,
         app.item_label(i.category),
         i.name,
         i.quantity, i.unit_price, i.amount, i.back_amount,
         cu.name
    from public.night_visit_item i
    join public.night_visit v on v.id = i.visit_id
    left join public.night_customer cu on cu.id = v.customer_id
   where i.cast_id = p_cast
     and v.status = 'closed'
     and v.business_date between p_from and p_to
     and (p_category is null or i.category = p_category)
   order by v.business_date, i.punched_at;
end;
$$;


-- ----------------------------------------------------------------------------
--  3. 種類ごとの合計
--     「指名 12本 ／ 指名料 合計 36,000円 ／ バック 24,000円」の形です。
-- ----------------------------------------------------------------------------
create or replace function public.night_payroll_item_summary(
  p_cast uuid, p_from date, p_to date
)
returns table (
  category      text,
  category_name text,
  cnt           integer,
  qty           integer,
  amount        integer,
  back_amount   integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare c public.night_cast;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select i.category,
         app.item_label(i.category),
         count(*)::integer,
         coalesce(sum(i.quantity), 0)::integer,
         coalesce(sum(i.amount), 0)::integer,
         coalesce(sum(i.back_amount), 0)::integer
    from public.night_visit_item i
    join public.night_visit v on v.id = i.visit_id
   where i.cast_id = p_cast
     and v.status = 'closed'
     and v.business_date between p_from and p_to
   group by i.category
   order by
     case i.category
       when 'nomination' then 1 when 'douhan' then 2 when 'drink' then 3
       when 'bottle' then 4 when 'set' then 5 when 'extension' then 6
       when 'food' then 7 else 8 end;
end;
$$;


-- ----------------------------------------------------------------------------
--  4. 明細に添える内訳（印刷用にひとまとめ）
--
--     発行済みの明細IDを渡すと、その対象期間の内訳をまとめて返します。
--     画面はこれを1回呼ぶだけで、内訳つきの明細を出せます。
-- ----------------------------------------------------------------------------
create or replace function public.payslip_detail(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare p public.payslip;
begin
  select * into p from public.payslip where id = p_id;
  if not found then raise exception '明細が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この明細を見る権限がありません'; end if;
  if p.subject_kind <> 'night_cast' then
    raise exception 'この明細の内訳は、まだ用意していません';
  end if;

  return jsonb_build_object(
    'payslip_id', p.id,
    'subject_name', p.subject_name,
    'period_from', p.period_from,
    'period_to', p.period_to,
    'daily', coalesce((
      select jsonb_agg(to_jsonb(d) order by d.business_date)
        from public.night_payroll_daily(p.subject_id, p.period_from, p.period_to) d
    ), '[]'::jsonb),
    'summary', coalesce((
      select jsonb_agg(to_jsonb(s))
        from public.night_payroll_item_summary(p.subject_id, p.period_from, p.period_to) s
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.business_date, i.punched_hm)
        from public.night_payroll_items(p.subject_id, p.period_from, p.period_to, null) i
    ), '[]'::jsonb)
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  5. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_payroll_daily(uuid, date, date),
  public.night_payroll_items(uuid, date, date, text),
  public.night_payroll_item_summary(uuid, date, date),
  public.payslip_detail(uuid),
  app.item_label(text)
to authenticated;


-- ============================================================================
--  確認用
--   select * from public.night_payroll_daily('キャストID','2026-09-01','2026-09-30');
--   select * from public.night_payroll_items('キャストID','2026-09-01','2026-09-30','nomination');
--   select * from public.night_payroll_item_summary('キャストID','2026-09-01','2026-09-30');
-- ============================================================================
