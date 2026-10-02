-- ============================================================================
--  ナイトだんどり / 達成率スライド（時給とバック率が、個人売上の達成率で変わる）
--  029_ratio_slide.sql
--
--  貼り付け先： SQL Editor（001 → 004 → 015 → だんどり共通_017-027 のあと）
--  何度流しても壊れません。
--
--  【しくみ】
--    達成率 ＝ その期間の個人売上（卓についた間に付いた売上の小計）
--            ÷ 時給換算の月給（基本時給 × 勤務時間） × 100
--
--    キャストの wage_rules に、こう書けます（既存の nomination / sales はそのまま使えます）：
--      [{"type":"ratio","from":150,"wage":2500},
--       {"type":"ratio","from":200,"wage":2500,"back_rate":20},
--       {"type":"ratio","from":300,"wage":3000,"back_rate":20}]
--
--    ・wage      … 達成したら、この時給にする（満たしたもののうち、いちばん高い時給）
--    ・back_rate … 達成したら、バックが付く明細のバック率を、少なくともこの % にする
--                  （例：ボトル 10% → 20%。もともと 25% のドリンクは 25% のまま）
--                  バックが付かない明細（セット・ソーダなど）には付きません
--
--  給与の試算（night_payroll_preview）に「達成率」「うち達成ボーナス」の列が増えます。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. 達成率
-- ----------------------------------------------------------------------------
create or replace function app.achieved_pct(p_cast uuid, p_sales integer, p_minutes integer)
returns integer
language sql stable security definer set search_path = public, app
as $$
  select case
    when coalesce(p_minutes, 0) > 0 and c.hourly_wage > 0
      then floor(coalesce(p_sales, 0) * 100.0 / (c.hourly_wage * p_minutes / 60.0))::integer
    else 0 end
  from public.night_cast c where c.id = p_cast;
$$;


-- ----------------------------------------------------------------------------
--  2. 時給スライドの判定（達成率に対応した版）
--     満たしたもののうち、いちばん高い時給を採用。どれも満たさなければ基本時給。
-- ----------------------------------------------------------------------------
create or replace function app.wage_for(
  p_cast uuid, p_nominations integer, p_sales integer, p_minutes integer
) returns integer
language plpgsql stable security definer set search_path = public, app
as $$
declare c public.night_cast; rule jsonb; best integer; pct integer;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then return 0; end if;
  best := c.hourly_wage;
  pct  := app.achieved_pct(p_cast, p_sales, p_minutes);

  for rule in select * from jsonb_array_elements(coalesce(c.wage_rules, '[]'::jsonb)) loop
    if (rule->>'type') = 'nomination'
       and coalesce(p_nominations, 0) >= coalesce((rule->>'from')::integer, 0) then
      best := greatest(best, coalesce((rule->>'wage')::integer, 0));
    elsif (rule->>'type') = 'sales'
       and coalesce(p_sales, 0) >= coalesce((rule->>'from')::integer, 0) then
      best := greatest(best, coalesce((rule->>'wage')::integer, 0));
    elsif (rule->>'type') = 'ratio'
       and pct >= coalesce((rule->>'from')::integer, 0) then
      best := greatest(best, coalesce((rule->>'wage')::integer, 0));
    end if;
  end loop;
  return best;
end;
$$;

-- 3引数の版は、前からの呼び出し（勤務時間なし）のために残します
create or replace function app.wage_for(
  p_cast uuid, p_nominations integer, p_sales integer
) returns integer
language sql stable security definer set search_path = public, app
as $$ select app.wage_for(p_cast, p_nominations, p_sales, null::integer); $$;


-- ----------------------------------------------------------------------------
--  3. 達成で上がるバック率（下限）。該当なしなら 0
-- ----------------------------------------------------------------------------
create or replace function app.back_floor_for(
  p_cast uuid, p_nominations integer, p_sales integer, p_minutes integer
) returns numeric
language plpgsql stable security definer set search_path = public, app
as $$
declare c public.night_cast; rule jsonb; best numeric := 0; pct integer; hit boolean;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then return 0; end if;
  pct := app.achieved_pct(p_cast, p_sales, p_minutes);

  for rule in select * from jsonb_array_elements(coalesce(c.wage_rules, '[]'::jsonb)) loop
    if (rule->>'back_rate') is null then continue; end if;
    hit := case rule->>'type'
      when 'nomination' then coalesce(p_nominations, 0) >= coalesce((rule->>'from')::integer, 0)
      when 'sales'      then coalesce(p_sales, 0)       >= coalesce((rule->>'from')::integer, 0)
      when 'ratio'      then pct                        >= coalesce((rule->>'from')::integer, 0)
      else false end;
    if hit then best := greatest(best, (rule->>'back_rate')::numeric); end if;
  end loop;
  return best;
end;
$$;

-- 1明細のバックを、下限の率で引き上げる（もともとバックが付く明細だけ）
create or replace function app.back_with_floor(p_back integer, p_amount integer, p_floor numeric)
returns integer
language sql immutable
as $$
  select case when coalesce(p_back, 0) > 0 and coalesce(p_floor, 0) > 0
              then greatest(p_back, floor(p_amount * p_floor / 100.0)::integer)
              else coalesce(p_back, 0) end;
$$;


-- ----------------------------------------------------------------------------
--  4. 給与の試算（列が増えるので、いったん消して作り直します）
--     （017-027 の「ふた」が付いていれば、それも消して、最後に付け直します）
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
  deduction      integer,
  advance        integer,
  net_amount     integer,
  below_min_wage boolean,
  confirmed      boolean,
  achieved_pct   integer,     -- 達成率（%）
  back_bonus     integer      -- バックのうち、達成で上がったぶん
)
language plpgsql stable security definer set search_path = public, app
as $$
declare st public.store;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p_store;

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
    select i.cast_id,
           count(*) filter (where i.category = 'nomination')::integer as noms,
           count(*) filter (where i.category = 'douhan')::integer     as dous,
           count(*) filter (where i.category = 'drink')::integer      as drks,
           coalesce(sum(i.amount),0)::integer      as sales,
           coalesce(sum(i.back_amount),0)::integer as back
      from public.night_visit_item i
      join public.night_visit v on v.id = i.visit_id
     where i.store_id = p_store and v.status = 'closed'
       and v.business_date between p_from and p_to
       and i.cast_id is not null
     group by i.cast_id
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
           coalesce(p.noms,0)    as noms,
           coalesce(p.dous,0)    as dous,
           coalesce(p.drks,0)    as drks,
           coalesce(p.sales,0)   as sales,
           coalesce(p.back,0)    as back,
           coalesce(j.allw,0)    as allw,
           coalesce(j.dedu,0)    as dedu,
           coalesce(y.adv,0)     as adv
      from public.night_cast c
      left join att  a on a.cast_id = c.id
      left join perf p on p.cast_id = c.id
      left join adj  j on j.cast_id = c.id
      left join pay  y on y.cast_id = c.id
     where c.store_id = p_store
       and (c.is_active or a.cast_id is not null or p.cast_id is not null)
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
                          and v.business_date between p_from and p_to), 0)
           else 0 end::integer as bns
      from calc c
  )
  select c.id, c.name, c.minutes, c.days, c.late,
         c.noms, c.dous, c.drks, c.sales,
         c.hourly_wage,
         c.hourly,
         (round(c.minutes / 60.0 * c.hourly))::integer as wage_amount,
         (c.back + b.bns)::integer,
         c.allw,
         c.dedu,
         c.adv,
         ((round(c.minutes / 60.0 * c.hourly))::integer + c.back + b.bns + c.allw - c.dedu - c.adv)::integer,
         (st.min_wage > 0 and c.hourly < st.min_wage),
         exists (select 1 from public.night_payroll pr
                  where pr.cast_id = c.id and pr.period_from = p_from and pr.period_to = p_to),
         c.pct,
         b.bns
    from calc c
    join bonus b on b.id = c.id
   order by c.name;
end;
$$;

grant execute on function public.night_payroll_preview(uuid, date, date) to authenticated;
grant execute on function app.wage_for(uuid, integer, integer, integer) to authenticated;
grant execute on function app.achieved_pct(uuid, integer, integer) to authenticated;
grant execute on function app.back_floor_for(uuid, integer, integer, integer) to authenticated;
grant execute on function app.back_with_floor(integer, integer, numeric) to authenticated;


-- ----------------------------------------------------------------------------
--  5. 日ごとの内訳も、同じ時給・同じバック率で出す
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
declare c public.night_cast; v_hourly integer; v_noms integer; v_sales integer; v_minutes integer; v_floor numeric;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  -- 期間ぜんぶの本指名本数・売上・勤務時間から、適用される時給とバック率を決めます
  select count(*) filter (where i.category = 'nomination')::integer,
         coalesce(sum(i.amount), 0)::integer
    into v_noms, v_sales
    from public.night_visit_item i
    join public.night_visit v on v.id = i.visit_id
   where i.cast_id = p_cast and v.status = 'closed'
     and v.business_date between p_from and p_to;

  select coalesce(sum(
           case when a.clock_in is not null and a.clock_out is not null
                then greatest(extract(epoch from (a.clock_out - a.clock_in))::integer / 60, 0)
                else 0 end), 0)::integer
    into v_minutes
    from public.night_attendance a
   where a.cast_id = p_cast and a.business_date between p_from and p_to;

  v_hourly := app.wage_for(p_cast, coalesce(v_noms, 0), coalesce(v_sales, 0), v_minutes);
  v_floor  := app.back_floor_for(p_cast, coalesce(v_noms, 0), coalesce(v_sales, 0), v_minutes);

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
           coalesce(sum(app.back_with_floor(i.back_amount, i.amount, v_floor)), 0)::integer as back
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

grant execute on function public.night_payroll_daily(uuid, date, date) to authenticated;


-- ----------------------------------------------------------------------------
--  6. 017-027 の「ふた」（店長以上だけ・本人だけ）を付け直す
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('app.add_guard(text,text,text)') is not null then
    raise notice '%', app.add_guard('public.night_payroll_preview(uuid,date,date)', 'boss', '給与の計算');
    raise notice '%', app.add_guard('public.night_payroll_daily(uuid,date,date)',   'mine', '給与の内訳');
  end if;
end $$;
