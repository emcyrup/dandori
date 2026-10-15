-- ============================================================================
--  ナイトだんどり / メニューの種類に「シャンパン」を足す
--  033_champagne.sql
--
--  貼り付け先： SQL Editor（001 … 032 のあと）。何度流しても壊れません。
--  これまで「ボトル」にまとめていたシャンパンを、売上の内訳や伝票の画面で分けて見られるようにします。
--  あわせて、売上画面の「キャスト別の売上」を折半の店舗では給与と同じ数え方（小計 ÷ 人数、指名 ＝ ついた卓）にします。
--  種類は文字列（night_menu.category）なので、表の作り直しは要りません。
--  給与のバックの計算は種類を見ていない（明細ごとの率と、折半の予備バック）ので、変わりません。
-- ============================================================================
\set ON_ERROR_STOP on

-- 種類の呼び名（給与の内訳・明細が使う）
create or replace function app.item_label(p_category text)
returns text language sql immutable as $$
  select case p_category
    when 'nomination' then '指名'
    when 'douhan'     then '同伴'
    when 'drink'      then 'ドリンク'
    when 'bottle'     then 'ボトル'
    when 'champagne'  then 'シャンパン'
    when 'set'        then 'セット'
    when 'extension'  then '延長'
    when 'food'       then 'フード'
    else 'その他' end;
$$;

-- 売上の内訳（「何で売れているか」）
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
           when 'drink' then 'ドリンク' when 'bottle' then 'ボトル' when 'champagne' then 'シャンパン'
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

grant execute on function public.night_sales_category(uuid, date, date) to authenticated;


-- ----------------------------------------------------------------------------
--  キャスト別の売上（売上の画面）を、折半の店舗では給与と同じ数え方にする
--    seat_split の店舗：売上 ＝ 小計 ÷ ついた人数、指名 ＝ ついた卓の数、
--    バック ＝ ドリンク・同伴のバック ＋ 予備バック（基本の率）
--    それ以外の店舗：いままでどおり
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
declare st public.store; v_split boolean;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  v_split := coalesce(st.seat_split, false);

  return query
  select c.id, c.name,
         case when v_split then round(coalesce(s.sales,0))::integer else coalesce(p.sales,0) end,
         (coalesce(p.back,0) + coalesce(s.tback,0))::integer,
         case when v_split then coalesce(s.noms,0) + coalesce(p.noms,0) else coalesce(p.noms,0) end,
         coalesce(p.dous,0), coalesce(p.drks,0),
         coalesce(a.days,0)
    from public.night_cast c
    left join (
      select i.cast_id,
             coalesce(sum(i.amount),0)::integer      as sales,
             coalesce(sum(i.back_amount) filter (
               where not v_split or i.category in ('drink','douhan','nomination')),0)::integer as back,
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
      select x.cast_id,
             count(distinct x.visit_id)::integer as noms,
             coalesce(sum(x.sales), 0) as sales,
             floor(coalesce(sum(x.table_base), 0) * coalesce(st.table_back_pct, 0) / 100.0)::integer as tback
        from app.seat_shares(p_store, p_from, p_to) x
       where v_split
       group by x.cast_id
    ) s on s.cast_id = c.id
    left join (
      select cast_id, count(*) filter (where clock_in is not null)::integer as days
        from public.night_attendance
       where store_id = p_store and business_date between p_from and p_to
       group by cast_id
    ) a on a.cast_id = c.id
   where c.store_id = p_store
     and (c.is_active or p.cast_id is not null or s.cast_id is not null)
   order by 3 desc, c.name;
end;
$$;

grant execute on function public.night_sales_cast(uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
