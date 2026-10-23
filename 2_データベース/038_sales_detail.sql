-- ============================================================================
--  ナイトだんどり / 2026-10-24 のご要望
--  038_sales_detail.sql
--
--  貼り付け先： SQL Editor（001 … 037 のあと）。何度流しても壊れません。
--
--   1. 日ごとの会計の内訳（卓ごとの明細・支払い）を見る：night_sales_visits
--   2. 試しに入れた売上（会計ずみの伝票）を消す：night_visit_delete を、締めたあとでも店長以上なら消せるように
--      （その日の締めは外れるので、締め直してもらう）
--   3. キャストを消す：night_cast_delete（出勤・売上・給与の記録がある人は消せない → 退店にする）
-- ============================================================================
\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
--  1. 日ごとの内訳
-- ----------------------------------------------------------------------------
create or replace function public.night_sales_visits(p_store uuid, p_date date)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', v.id, 'table_no', v.table_no, 'status', v.status,
      'guest', coalesce(c.name, v.guest_name), 'head_count', v.head_count,
      'entered_at', v.entered_at, 'closed_at', v.closed_at,
      'casts', coalesce((select string_agg(nc.name, '・' order by vc.seated_at)
                           from public.night_visit_cast vc join public.night_cast nc on nc.id = vc.cast_id
                          where vc.visit_id = v.id), (select nc.name from public.night_cast nc where nc.id = v.main_cast_id)),
      'subtotal', v.subtotal, 'service_charge', v.service_charge, 'tax', v.tax,
      'discount', v.discount, 'round_adj', coalesce(v.round_adj, 0), 'total', v.total,
      'items', coalesce((select jsonb_agg(jsonb_build_object(
                  'name', i.name, 'category', i.category, 'quantity', i.quantity,
                  'unit_price', i.unit_price, 'amount', i.amount,
                  'cast', (select nc.name from public.night_cast nc where nc.id = i.cast_id))
                  order by i.punched_at)
                 from public.night_visit_item i where i.visit_id = v.id), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('method', p.method, 'amount', p.amount) order by p.created_at)
                 from public.night_payment p where p.visit_id = v.id), '[]'::jsonb)
    ) order by v.entered_at)
    from public.night_visit v
    left join public.night_customer c on c.id = v.customer_id
    where v.store_id = p_store and v.business_date = p_date
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.night_sales_visits(uuid, date) to authenticated;

-- ----------------------------------------------------------------------------
--  2. 伝票を消す（締めたあとでも、店長以上なら。その日の締めは外れる）
-- ----------------------------------------------------------------------------
create or replace function public.night_visit_delete(p_visit uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; v public.night_visit; n_items integer; n_pay integer; n_close integer := 0;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if v.status <> 'open' and not app.is_boss() then
    raise exception '会計ずみの伝票を消せるのは、店長以上の方だけです';
  end if;

  -- 明細 → 伝票 の順に消す（明細のトリガが伝票を見に来るため）。支払い・ついたキャストは伝票と一緒に消える
  delete from public.night_visit_item where visit_id = p_visit;
  get diagnostics n_items = row_count;
  select count(*)::integer into n_pay from public.night_payment where visit_id = p_visit;
  delete from public.night_visit where id = p_visit;

  -- その日をもう締めてあったら、締めを外す（数字が変わるので、締め直してもらう）
  if v.status <> 'open' then
    delete from public.night_daily_close where store_id = v.store_id and business_date = v.business_date;
    get diagnostics n_close = row_count;
  end if;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (v.tenant_id, v.store_id, me.id, 'visit_delete', 'night_visit', p_visit::text,
          jsonb_build_object('table_no', v.table_no, 'business_date', v.business_date,
                             'status', v.status, 'total', v.total, 'items', n_items, 'payments', n_pay,
                             'reopened_day', n_close > 0));
  return jsonb_build_object('ok', true, 'items', n_items, 'payments', n_pay, 'reopened_day', n_close > 0,
    'message', case when n_close > 0 then '消しました。' || to_char(v.business_date, 'FMMM月FMDD日') || ' の締めは外れたので、締め直してください'
                    else '消しました' end);
end;
$$;

-- ----------------------------------------------------------------------------
--  3. キャストを消す
-- ----------------------------------------------------------------------------
create or replace function public.night_cast_delete(p_cast uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; n integer;
begin
  select * into me from app.me();
  if me.id is null or not app.is_boss() then raise exception 'キャストを消せるのは、店長以上の方だけです'; end if;
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'そのキャストは見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select (select count(*) from public.night_attendance where cast_id = p_cast)
       + (select count(*) from public.night_visit_item where cast_id = p_cast)
       + (select count(*) from public.night_payroll where cast_id = p_cast)
       + (select count(*) from public.night_payout where cast_id = p_cast)
       + (select count(*) from public.night_adjustment where cast_id = p_cast)
       + (select count(*) from public.night_visit_cast where cast_id = p_cast)
    into n;
  if n > 0 then
    raise exception '% さんには出勤・売上・給与の記録があるので消せません。「編集」で状態を「退店」にしてください', c.name;
  end if;

  delete from public.night_cast where id = p_cast;
  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (c.tenant_id, c.store_id, me.id, 'cast_delete', 'night_cast', p_cast::text, jsonb_build_object('name', c.name));
  return jsonb_build_object('ok', true, 'name', c.name);
end;
$$;
grant execute on function public.night_cast_delete(uuid) to authenticated;

notify pgrst, 'reload schema';
