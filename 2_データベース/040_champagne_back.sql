-- ============================================================================
--  ナイトだんどり / シャンパンにもバック（2026-10-27）
--  040_champagne_back.sql
--
--  貼り付け先： SQL Editor（001 … 039 のあと）。何度流しても壊れません。
--
--  折半の店舗（seat_split）では、これまで明細のバックはドリンク・同伴・指名だけで、
--  シャンパンは小計の一部として、ついたキャストで均等に分ける「予備バック」に入っていました。
--  これを、シャンパンもドリンクと同じく「誰にバックを付けますか？」で選んだキャストに付けるようにします。
--   ・選んだキャストに、シャンパンのバック（料金マスタのバック率。達成でバック率が上がればその率）
--   ・二重払いにならないよう、バックを付けたシャンパンは予備バックの元（小計の取り分）から外す
--   ・個人売上（達成率の元）は、これまでどおり卓の小計を人数で割ったもの
--   ・「バックなしで打つ」にしたシャンパンは、これまでどおり予備バックに入る
-- ============================================================================
\set ON_ERROR_STOP on

-- 1. 明細のバックとして数える種類に、シャンパンを足す（給与の試算・月別・内訳・売上のキャスト別・達成率の分母）
do $$
declare r record; def text; n integer := 0;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname in ('public', 'app') and p.prokind = 'f'
       and p.prosrc like '%(''drink'',''douhan'',''nomination'')%'
  loop
    def := pg_get_functiondef(r.oid);
    def := replace(def, '(''drink'',''douhan'',''nomination'')', '(''drink'',''douhan'',''nomination'',''champagne'')');
    execute def;
    n := n + 1;
  end loop;
  raise notice 'シャンパンを明細のバックに数える関数：% 件', n;
end $$;

-- 2. 予備バックの元から、バックを付けたシャンパンを外す
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
  ch as (   -- バックを付けたシャンパン（選んだキャストに明細のバックで払う）
    select i.visit_id, sum(i.amount)::numeric as amt
      from public.night_visit_item i
      join public.night_visit v on v.id = i.visit_id
     where v.store_id = p_store and v.status = 'closed'
       and v.business_date between p_from and p_to
       and i.category = 'champagne' and i.cast_id is not null and i.back_amount > 0
     group by i.visit_id
  )
  select vc.cast_id, v.business_date, v.id,
         v.subtotal / n.people,
         greatest(v.subtotal - coalesce(ch.amt, 0), 0) / n.people
    from public.night_visit_cast vc
    join n on n.visit_id = vc.visit_id
    join public.night_visit v on v.id = vc.visit_id
    left join ch on ch.visit_id = v.id;
$$;

notify pgrst, 'reload schema';
