-- ============================================================================
--  ナイトだんどり / 売上の集計
--  008_sales.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜006 を先に実行しておいてください）
--
--  当日の速報と、期間を指定した売上の集計です。
--  何度実行しても壊れません。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. 当日の速報
--     締め済みの売上に加えて、いま開いている卓の「見込み」も返します。
-- ----------------------------------------------------------------------------
create or replace function public.night_sales_today(p_store uuid)
returns table (
  business_date  date,
  closed_visits  integer,
  closed_guests  integer,
  closed_sales   integer,
  cash           integer,
  card           integer,
  credit         integer,
  open_visits    integer,
  open_estimate  integer,
  total_estimate integer,
  per_guest      integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare st public.store; bd date;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  bd := app.business_date(now(), st.day_cutoff);

  return query
  with c as (
    select count(*)::integer as v, coalesce(sum(head_count),0)::integer as g,
           coalesce(sum(total),0)::integer as s,
           coalesce(sum(paid_cash),0)::integer as cash,
           coalesce(sum(paid_card),0)::integer as card,
           coalesce(sum(paid_credit),0)::integer as credit
      from public.night_visit
     where store_id = p_store and business_date = bd and status = 'closed'
  ),
  o as (
    select count(*)::integer as v, coalesce(sum(total),0)::integer as s
      from public.night_visit
     where store_id = p_store and business_date = bd and status = 'open'
  )
  select bd, c.v, c.g, c.s, c.cash, c.card, c.credit, o.v, o.s, (c.s + o.s),
         case when c.g > 0 then (c.s / c.g)::integer else 0 end
    from c, o;
end;
$$;


-- ----------------------------------------------------------------------------
--  2. 日別の売上（期間指定）
--     売上のない日も 0 の行で返します（グラフが途切れないように）
-- ----------------------------------------------------------------------------
create or replace function public.night_sales_daily(
  p_store uuid, p_from date, p_to date
) returns table (
  business_date date,
  visits        integer,
  guests        integer,
  sales         integer,
  cash          integer,
  card          integer,
  credit        integer,
  service       integer,
  tax           integer,
  discount      integer,
  per_guest     integer,
  closed        boolean
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select d.day::date,
         coalesce(v.visits,0), coalesce(v.guests,0), coalesce(v.sales,0),
         coalesce(v.cash,0), coalesce(v.card,0), coalesce(v.credit,0),
         coalesce(v.service,0), coalesce(v.tax,0), coalesce(v.discount,0),
         case when coalesce(v.guests,0) > 0
              then (v.sales / v.guests)::integer else 0 end,
         (dc.id is not null)
    from generate_series(p_from, p_to, interval '1 day') as d(day)
    left join (
      select business_date,
             count(*)::integer                     as visits,
             coalesce(sum(head_count),0)::integer  as guests,
             coalesce(sum(total),0)::integer       as sales,
             coalesce(sum(paid_cash),0)::integer   as cash,
             coalesce(sum(paid_card),0)::integer   as card,
             coalesce(sum(paid_credit),0)::integer as credit,
             coalesce(sum(service_charge),0)::integer as service,
             coalesce(sum(tax),0)::integer         as tax,
             coalesce(sum(discount),0)::integer    as discount
        from public.night_visit
       where store_id = p_store and status = 'closed'
         and business_date between p_from and p_to
       group by business_date
    ) v on v.business_date = d.day::date
    left join public.night_daily_close dc
      on dc.store_id = p_store and dc.business_date = d.day::date
   order by d.day;
end;
$$;


-- ----------------------------------------------------------------------------
--  3. 区分ごとの内訳（セット・指名・ドリンク…）
-- ----------------------------------------------------------------------------
create or replace function public.night_sales_category(
  p_store uuid, p_from date, p_to date
) returns table (
  category  text,
  label     text,
  qty       integer,
  amount    integer,
  share     numeric
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare v_total integer;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  select coalesce(sum(i.amount),0) into v_total
    from public.night_visit_item i
    join public.night_visit v on v.id = i.visit_id
   where i.store_id = p_store and v.status = 'closed'
     and v.business_date between p_from and p_to;

  return query
  select i.category,
         case i.category
           when 'set' then 'セット' when 'extension' then '延長'
           when 'nomination' then '指名' when 'douhan' then '同伴'
           when 'drink' then 'ドリンク' when 'bottle' then 'ボトル'
           when 'food' then 'フード' else 'その他' end,
         coalesce(sum(i.quantity),0)::integer,
         coalesce(sum(i.amount),0)::integer,
         case when v_total > 0
              then round(sum(i.amount) * 100.0 / v_total, 1) else 0 end
    from public.night_visit_item i
    join public.night_visit v on v.id = i.visit_id
   where i.store_id = p_store and v.status = 'closed'
     and v.business_date between p_from and p_to
   group by i.category
   order by 4 desc;
end;
$$;


-- ----------------------------------------------------------------------------
--  4. キャスト別の売上
-- ----------------------------------------------------------------------------
create or replace function public.night_sales_cast(
  p_store uuid, p_from date, p_to date
) returns table (
  cast_id     uuid,
  cast_name   text,
  sales       integer,
  back        integer,
  nominations integer,
  douhans     integer,
  drinks      integer,
  work_days   integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select c.id, c.name,
         coalesce(p.sales,0), coalesce(p.back,0),
         coalesce(p.noms,0), coalesce(p.dous,0), coalesce(p.drks,0),
         coalesce(a.days,0)
    from public.night_cast c
    left join (
      select i.cast_id,
             coalesce(sum(i.amount),0)::integer      as sales,
             coalesce(sum(i.back_amount),0)::integer as back,
             count(*) filter (where i.category = 'nomination')::integer as noms,
             count(*) filter (where i.category = 'douhan')::integer     as dous,
             count(*) filter (where i.category = 'drink')::integer      as drks
        from public.night_visit_item i
        join public.night_visit v on v.id = i.visit_id
       where i.store_id = p_store and v.status = 'closed'
         and v.business_date between p_from and p_to
         and i.cast_id is not null
       group by i.cast_id
    ) p on p.cast_id = c.id
    left join (
      select cast_id, count(*) filter (where clock_in is not null)::integer as days
        from public.night_attendance
       where store_id = p_store and business_date between p_from and p_to
       group by cast_id
    ) a on a.cast_id = c.id
   where c.store_id = p_store
     and (c.is_active or p.cast_id is not null)
   order by coalesce(p.sales,0) desc, c.name;
end;
$$;


-- ----------------------------------------------------------------------------
--  5. お客様別の売上（上位）
-- ----------------------------------------------------------------------------
create or replace function public.night_sales_customer(
  p_store uuid, p_from date, p_to date, p_limit integer default 20
) returns table (
  customer_id uuid,
  name        text,
  visits      integer,
  sales       integer,
  per_visit   integer,
  last_visit  date
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select cu.id, cu.name,
         count(*)::integer,
         coalesce(sum(v.total),0)::integer,
         (coalesce(sum(v.total),0) / greatest(count(*),1))::integer,
         max(v.business_date)
    from public.night_visit v
    join public.night_customer cu on cu.id = v.customer_id
   where v.store_id = p_store and v.status = 'closed'
     and v.business_date between p_from and p_to
   group by cu.id, cu.name
   order by 4 desc
   limit greatest(p_limit, 1);
end;
$$;


-- ----------------------------------------------------------------------------
--  6. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_sales_today(uuid),
  public.night_sales_daily(uuid, date, date),
  public.night_sales_category(uuid, date, date),
  public.night_sales_cast(uuid, date, date),
  public.night_sales_customer(uuid, date, date, integer)
to authenticated;


-- ============================================================================
--  確認用
--   select * from public.night_sales_today((select id from store where name='三宮本店'));
--   select * from public.night_sales_daily(
--     (select id from store where name='三宮本店'), current_date - 7, current_date);
-- ============================================================================
