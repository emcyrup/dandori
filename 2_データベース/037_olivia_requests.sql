-- ============================================================================
--  ナイトだんどり / 2026-10-23 のご要望
--  037_olivia_requests.sql
--
--  貼り付け先： SQL Editor（001 … 036 のあと）。何度流しても壊れません。
--
--   1. ボトルの銘柄をプルダウンで選ぶ：メニューに「グループ」（焼酎・リキュール／ウイスキー など）を持たせ、
--      無い銘柄は卓の画面からその場で足せる（night_menu_add_bottle）
--   2. シフトの募集を「一週間ごと・月〜土」にできる（募集の単位 week6）
--   3. 卓を間違えたとき、伝票ごと消せる（night_visit_delete）
--   4. 一般スタッフが、自分のシフト希望だけ出せる（wish_my_links）
-- ============================================================================
\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
--  1. メニューのグループと、銘柄の追加
-- ----------------------------------------------------------------------------
alter table public.night_menu add column if not exists group_name text;
comment on column public.night_menu.group_name is 'プルダウンの見出し（焼酎・リキュール／ワイン／ウイスキー など）。空なら見出しなし';

-- 卓の画面から銘柄を足す（その店舗の人なら誰でも。バック率などは、同じ区分のほかの銘柄に合わせる）
create or replace function public.night_menu_add_bottle(
  p_store uuid, p_name text, p_price integer, p_group text default null, p_category text default 'bottle')
returns public.night_menu
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; ref public.night_menu; m public.night_menu; v_name text;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_category not in ('bottle', 'champagne') then raise exception 'ボトルかシャンパンだけ足せます'; end if;
  v_name := nullif(btrim(coalesce(p_name, '')), '');
  if v_name is null then raise exception '銘柄を入れてください'; end if;
  if coalesce(p_price, 0) < 0 then raise exception '料金が変です'; end if;
  select * into st from public.store where id = p_store;

  -- 同じ名前がすでにあれば、それを返す（止めてあったものは戻す）
  select * into m from public.night_menu
   where store_id = p_store and category = p_category and name = v_name limit 1;
  if found then
    if not m.is_active then
      update public.night_menu set is_active = true where id = m.id returning * into m;
    end if;
    return m;
  end if;

  -- バック・サービス料・税の付け方は、同じ区分のいちばん新しい銘柄に合わせる
  select * into ref from public.night_menu
   where store_id = p_store and category = p_category and is_active
   order by sort_order desc, created_at desc limit 1;

  insert into public.night_menu(
    tenant_id, store_id, category, name, unit_price, back_amount, back_rate,
    service_apply, tax_apply, sort_order, group_name)
  values (st.tenant_id, p_store, p_category, v_name, coalesce(p_price, 0),
          0, coalesce(ref.back_rate, 0),
          coalesce(ref.service_apply, true), coalesce(ref.tax_apply, true),
          coalesce(ref.sort_order, 100) + 1,
          nullif(btrim(coalesce(p_group, '')), ''))
  returning * into m;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (st.tenant_id, p_store, me.id, 'menu_add', 'night_menu', m.id::text,
          jsonb_build_object('name', v_name, 'price', coalesce(p_price, 0), 'category', p_category));
  return m;
end;
$$;
grant execute on function public.night_menu_add_bottle(uuid, text, integer, text, text) to authenticated;

-- ----------------------------------------------------------------------------
--  2. 募集の単位 week6（一週間ごと・月〜土）
-- ----------------------------------------------------------------------------
create or replace function app.wish_range(p_kind text, p_anchor date)
returns table (period_from date, period_to date)
language plpgsql immutable set search_path = public, app
as $$
declare f date; t date;
begin
  if p_kind = 'month' then
    f := date_trunc('month', p_anchor)::date;
    t := (f + interval '1 month - 1 day')::date;
  elsif p_kind = 'week' then
    f := p_anchor - ((extract(isodow from p_anchor)::integer - 1));
    t := f + 6;
  elsif p_kind = 'week6' then
    -- 月〜土。日曜に当たったら、つぎの週の月曜から
    if extract(isodow from p_anchor)::integer = 7 then
      f := p_anchor + 1;
    else
      f := p_anchor - ((extract(isodow from p_anchor)::integer - 1));
    end if;
    t := f + 5;
  else   -- half（半月ごと）
    if extract(day from p_anchor)::integer <= 15 then
      f := date_trunc('month', p_anchor)::date;
      t := f + 14;
    else
      f := (date_trunc('month', p_anchor) + interval '15 day')::date;
      t := (date_trunc('month', p_anchor) + interval '1 month - 1 day')::date;
    end if;
  end if;
  return query select f, t;
end;
$$;

create or replace function public.shift_period_open(
  p_store uuid, p_anchor date default null,
  p_kind text default null, p_deadline timestamptz default null)
returns public.shift_period
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; st public.store; r public.shift_period;
  v_kind text; v_anchor date; v_f date; v_t date; v_dl timestamptz;
begin
  select * into me from app.me();
  if me.id is null or me.role not in ('owner','manager') then
    raise exception '募集を開くには、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p_store;

  v_kind := coalesce(nullif(p_kind, ''), st.wish_cycle, 'half');
  if v_kind not in ('half','month','week','week6') then
    raise exception '募集の単位は、半月・月・週・週（月〜土） のどれかです';
  end if;

  -- 指定がなければ、いちばん新しい募集のつぎ（無ければ、いまの期間のつぎ）を作ります
  if p_anchor is not null then
    v_anchor := p_anchor;
  else
    select max(period_to) + 1 into v_anchor from public.shift_period where store_id = p_store;
    if v_anchor is null or v_anchor < current_date then
      select w.period_to + 1 into v_anchor from app.wish_range(v_kind, current_date) w;
    end if;
  end if;

  select w.period_from, w.period_to into v_f, v_t from app.wish_range(v_kind, v_anchor) w;

  -- 締切は、日本時間の「その日の23:59」です
  v_dl := coalesce(p_deadline,
                   ((v_f - coalesce(st.wish_deadline_days, 5)) + time '23:59')
                     at time zone 'Asia/Tokyo');

  insert into public.shift_period(
    tenant_id, store_id, kind, period_from, period_to, deadline_at, created_by)
  values (st.tenant_id, p_store, v_kind, v_f, v_t, v_dl, me.id)
  on conflict (store_id, period_from, period_to) do update
    set deadline_at = excluded.deadline_at, status = 'open'
  returning * into r;

  if not exists (select 1 from public.shift_slot s where s.store_id = p_store) then
    perform app.shift_slot_seed_core(p_store);
  end if;

  return r;
end;
$$;

-- ----------------------------------------------------------------------------
--  3. 伝票を丸ごと消す
--     開いている卓は、その店舗の人なら誰でも。会計ずみの伝票は店長以上だけ（その日を締めたあとは消せない）
-- ----------------------------------------------------------------------------
create or replace function public.night_visit_delete(p_visit uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; v public.night_visit; n_items integer; n_pay integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if v.status <> 'open' then
    if not app.is_boss() then raise exception '会計ずみの伝票を消せるのは、店長以上の方だけです'; end if;
    if exists (select 1 from public.night_daily_close d
                where d.store_id = v.store_id and d.business_date = v.business_date) then
      raise exception 'その日はもう締めてあるので消せません。締めを開け直してから消してください';
    end if;
  end if;

  -- 明細 → 伝票 の順に消す（明細のトリガが伝票を見に来るため）。支払い・ついたキャストは伝票と一緒に消える
  delete from public.night_visit_item where visit_id = p_visit;
  get diagnostics n_items = row_count;
  select count(*)::integer into n_pay from public.night_payment where visit_id = p_visit;
  delete from public.night_visit where id = p_visit;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (v.tenant_id, v.store_id, me.id, 'visit_delete', 'night_visit', p_visit::text,
          jsonb_build_object('table_no', v.table_no, 'business_date', v.business_date,
                             'status', v.status, 'total', v.total, 'items', n_items, 'payments', n_pay));
  return jsonb_build_object('ok', true, 'items', n_items, 'payments', n_pay);
end;
$$;
grant execute on function public.night_visit_delete(uuid) to authenticated;

-- ----------------------------------------------------------------------------
--  4. 自分のシフト希望のリンク（一般スタッフ用）
--     ログインしている人が名簿のどの行か（app.my_subject）を見て、受付中の募集ごとに本人用リンクを返す
-- ----------------------------------------------------------------------------
create or replace function public.wish_my_links(p_store uuid, p_base text default null)
returns table (period_id uuid, period_from date, period_to date, deadline_at timestamptz,
               period_status text, subject_kind text, subject_id uuid, name text,
               wish_status text, url text)
language plpgsql security definer set search_path = public, app
as $$
#variable_conflict use_column
declare p record; s record; j jsonb;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  for p in select * from public.shift_period sp
            where sp.store_id = p_store and sp.period_to >= current_date - 7
            order by sp.period_from desc limit 6 loop
    for s in select m.subject_kind, m.subject_id, pe.name
               from app.my_subject() m
               join public.shift_people(p_store) pe
                 on pe.subject_kind = m.subject_kind and pe.subject_id = m.subject_id loop
      j := public.wish_link(p.id, s.subject_kind, s.subject_id, p_base);
      return query
        select p.id, p.period_from, p.period_to, p.deadline_at, p.status,
               s.subject_kind, s.subject_id, s.name,
               coalesce((select w.status from public.shift_wish w
                          where w.period_id = p.id and w.subject_kind = s.subject_kind
                            and w.subject_id = s.subject_id), 'draft'),
               j->>'url';
    end loop;
  end loop;
end;
$$;
grant execute on function public.wish_my_links(uuid, text) to authenticated;

notify pgrst, 'reload schema';
