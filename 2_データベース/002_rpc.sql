-- ============================================================================
--  ナイトだんどり / 伝票の操作関数（RPC）
--  002_rpc.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               このファイルの中身を全部貼って Run
--               （001_foundation.sql を先に実行しておいてください）
--
--  お金の計算をブラウザ側に置かないための関数です。
--  卓を開く・明細を打つ・締める・日締め の4つをここに集めています。
--  何度実行しても壊れません。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  卓を開く
--    営業日は店舗の day_cutoff から自動で決めます（深夜2時なら前日扱い）
-- ----------------------------------------------------------------------------
create or replace function public.night_open_visit(
  p_store       uuid,
  p_table_no    text default null,
  p_customer    uuid default null,
  p_guest_name  text default null,
  p_head_count  integer default 1,
  p_cast        uuid default null
) returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare
  st public.store;
  me public.staff;
  v  public.night_visit;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into st from public.store where id = p_store and tenant_id = me.tenant_id;
  if not found then raise exception '店舗が見つかりません'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  -- 同じ卓番がすでに開いていないか
  if p_table_no is not null and exists (
       select 1 from public.night_visit
        where store_id = p_store and status = 'open' and table_no = p_table_no) then
    raise exception '卓 % はすでに開いています', p_table_no;
  end if;

  insert into public.night_visit(
    tenant_id, store_id, business_date, table_no,
    customer_id, guest_name, head_count, main_cast_id, entered_at, status)
  values (
    me.tenant_id, p_store, app.business_date(now(), st.day_cutoff), p_table_no,
    p_customer, p_guest_name, greatest(p_head_count,1), p_cast, now(), 'open')
  returning * into v;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, p_store, me.id, 'open', 'night_visit', v.id::text,
          jsonb_build_object('table_no', p_table_no, 'head_count', p_head_count));

  return v;
end;
$$;


-- ----------------------------------------------------------------------------
--  明細を打つ
--    単価とバックは料金マスタから取り、その時点の値を明細に焼き付けます
--    （あとで料金を変えても、打った伝票は動きません）
-- ----------------------------------------------------------------------------
create or replace function public.night_add_item(
  p_visit    uuid,
  p_menu     uuid,
  p_quantity integer default 1,
  p_cast     uuid default null
) returns public.night_visit_item
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff;
  v  public.night_visit;
  m  public.night_menu;
  it public.night_visit_item;
  v_amount integer;
  v_back   integer;
  v_qty    integer := greatest(coalesce(p_quantity,1), 1);
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if v.status <> 'open' then raise exception 'この伝票は締め済みです。打ち直すには締めを解除してください'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into m from public.night_menu where id = p_menu and store_id = v.store_id and is_active;
  if not found then raise exception 'メニューが見つかりません'; end if;

  v_amount := m.unit_price * v_qty;
  v_back   := m.back_amount * v_qty + floor(v_amount * m.back_rate / 100.0);

  -- バックが出るのにキャストが指定されていなければ、卓の担当を充てます
  insert into public.night_visit_item(
    tenant_id, store_id, visit_id, menu_id, category, name,
    unit_price, quantity, amount, cast_id, back_amount,
    service_apply, tax_apply, punched_at, punched_by)
  values (
    v.tenant_id, v.store_id, v.id, m.id, m.category, m.name,
    m.unit_price, v_qty, v_amount,
    coalesce(p_cast, case when v_back > 0 then v.main_cast_id else null end),
    case when coalesce(p_cast, v.main_cast_id) is null then 0 else v_back end,
    m.service_apply, m.tax_apply, now(), me.id)
  returning * into it;

  return it;
end;
$$;


-- ----------------------------------------------------------------------------
--  明細を消す
-- ----------------------------------------------------------------------------
create or replace function public.night_remove_item(p_item uuid)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff;
  it public.night_visit_item;
  v  public.night_visit;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into it from public.night_visit_item where id = p_item;
  if not found then return false; end if;

  select * into v from public.night_visit where id = it.visit_id;
  if v.status <> 'open' then raise exception '締め済みの伝票は変更できません'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  delete from public.night_visit_item where id = p_item;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (v.tenant_id, v.store_id, me.id, 'delete', 'night_visit_item', p_item::text,
          jsonb_build_object('name', it.name, 'amount', it.amount));

  return true;
end;
$$;


-- ----------------------------------------------------------------------------
--  値引きを入れる
-- ----------------------------------------------------------------------------
create or replace function public.night_set_discount(p_visit uuid, p_discount integer)
returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare v public.night_visit; me public.staff;
begin
  select * into me from app.me();
  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if v.status <> 'open' then raise exception '締め済みの伝票は変更できません'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.night_visit set discount = greatest(coalesce(p_discount,0),0) where id = p_visit;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (v.tenant_id, v.store_id, me.id, 'discount', 'night_visit', p_visit::text,
          jsonb_build_object('discount', p_discount));

  return public.night_recalc_visit(p_visit);
end;
$$;


-- ----------------------------------------------------------------------------
--  締める（会計）
--    現金・カード・売掛の合計が伝票の合計と一致しないと、締まりません。
--    売掛にした分は、自動でツケの台帳に起票されます。
-- ----------------------------------------------------------------------------
create or replace function public.night_close_visit(
  p_visit  uuid,
  p_cash   integer default 0,
  p_card   integer default 0,
  p_credit integer default 0,
  p_due_on date default null,
  p_note   text default null
) returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff;
  v  public.night_visit;
  v_cash integer := greatest(coalesce(p_cash,0),0);
  v_card integer := greatest(coalesce(p_card,0),0);
  v_cred integer := greatest(coalesce(p_credit,0),0);
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into v from public.night_visit where id = p_visit for update;
  if not found then raise exception '伝票が見つかりません'; end if;
  if v.status <> 'open' then raise exception 'この伝票はすでに締め済みです'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  -- 念のため最新の金額で計算し直してから突き合わせます
  v := public.night_recalc_visit(p_visit);

  if v_cash + v_card + v_cred <> v.total then
    raise exception '支払いの合計（%円）が伝票の合計（%円）と合いません',
      v_cash + v_card + v_cred, v.total;
  end if;

  if v_cred > 0 and v.customer_id is null then
    raise exception '売掛にするには、お客様を伝票に紐づけてください';
  end if;

  if v_cash > 0 then
    insert into public.night_payment(tenant_id, store_id, visit_id, method, amount, created_by)
    values (v.tenant_id, v.store_id, v.id, 'cash', v_cash, me.id);
  end if;
  if v_card > 0 then
    insert into public.night_payment(tenant_id, store_id, visit_id, method, amount, created_by)
    values (v.tenant_id, v.store_id, v.id, 'card', v_card, me.id);
  end if;
  if v_cred > 0 then
    insert into public.night_payment(tenant_id, store_id, visit_id, method, amount, created_by)
    values (v.tenant_id, v.store_id, v.id, 'credit', v_cred, me.id);

    insert into public.night_receivable(
      tenant_id, store_id, customer_id, visit_id, occurred_on, amount, due_on, note)
    values (v.tenant_id, v.store_id, v.customer_id, v.id, v.business_date, v_cred,
            coalesce(p_due_on, v.business_date + 30), p_note);
  end if;

  update public.night_visit
     set status = 'closed',
         left_at = now(),
         paid_cash = v_cash, paid_card = v_card, paid_credit = v_cred,
         closed_by = me.id, closed_at = now(),
         note = coalesce(p_note, note)
   where id = p_visit
   returning * into v;

  -- お客様の来店記録を更新
  if v.customer_id is not null then
    update public.night_customer
       set visit_count = visit_count + 1,
           last_visit_on = v.business_date,
           first_visit_on = coalesce(first_visit_on, v.business_date)
     where id = v.customer_id;
  end if;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (v.tenant_id, v.store_id, me.id, 'close', 'night_visit', v.id::text,
          jsonb_build_object('total', v.total, 'cash', v_cash, 'card', v_card, 'credit', v_cred));

  return v;
end;
$$;


-- ----------------------------------------------------------------------------
--  締めを解除する（打ち間違いの訂正用 / owner・manager のみ）
--    売掛に入金があった場合は解除できません
-- ----------------------------------------------------------------------------
create or replace function public.night_reopen_visit(p_visit uuid)
returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; v public.night_visit;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '締めの解除は、店長以上の権限が必要です';
  end if;

  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  if exists (select 1 from public.night_receivable r
              where r.visit_id = p_visit and r.paid_amount > 0) then
    raise exception 'この伝票の売掛にはすでに入金があります。解除できません';
  end if;

  delete from public.night_receivable where visit_id = p_visit;
  delete from public.night_payment    where visit_id = p_visit;

  if v.customer_id is not null then
    update public.night_customer
       set visit_count = greatest(visit_count - 1, 0)
     where id = v.customer_id;
  end if;

  update public.night_visit
     set status = 'open', left_at = null,
         paid_cash = 0, paid_card = 0, paid_credit = 0,
         closed_by = null, closed_at = null
   where id = p_visit
   returning * into v;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (v.tenant_id, v.store_id, me.id, 'reopen', 'night_visit', v.id::text, '{}'::jsonb);

  return v;
end;
$$;


-- ----------------------------------------------------------------------------
--  日締め（その日の売上と現金を確定する）
--    p_cash_counted に、実際に数えた現金を入れます
-- ----------------------------------------------------------------------------
create or replace function public.night_close_day(
  p_store        uuid,
  p_date         date,
  p_cash_counted integer default 0,
  p_note         text default null
) returns public.night_daily_close
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff;
  r  public.night_daily_close;
  v_sales integer; v_cash integer; v_card integer; v_credit integer; v_count integer;
  v_open  integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  select count(*) into v_open
    from public.night_visit
   where store_id = p_store and business_date = p_date and status = 'open';
  if v_open > 0 then
    raise exception '開いたままの卓が%件あります。先に締めてください', v_open;
  end if;

  select coalesce(sum(total),0), coalesce(sum(paid_cash),0),
         coalesce(sum(paid_card),0), coalesce(sum(paid_credit),0), count(*)
    into v_sales, v_cash, v_card, v_credit, v_count
    from public.night_visit
   where store_id = p_store and business_date = p_date and status = 'closed';

  insert into public.night_daily_close(
    tenant_id, store_id, business_date, sales_total, cash_expected, cash_counted,
    card_total, credit_total, visit_count, note, closed_by, closed_at)
  values (
    me.tenant_id, p_store, p_date, v_sales, v_cash, greatest(coalesce(p_cash_counted,0),0),
    v_card, v_credit, v_count, p_note, me.id, now())
  on conflict (store_id, business_date) do update
    set sales_total = excluded.sales_total,
        cash_expected = excluded.cash_expected,
        cash_counted = excluded.cash_counted,
        card_total = excluded.card_total,
        credit_total = excluded.credit_total,
        visit_count = excluded.visit_count,
        note = excluded.note,
        closed_by = excluded.closed_by,
        closed_at = now()
  returning * into r;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, p_store, me.id, 'close_day', 'night_daily_close', r.id::text,
          jsonb_build_object('date', p_date, 'sales', v_sales, 'diff', r.cash_diff));

  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  売掛に入金する
-- ----------------------------------------------------------------------------
create or replace function public.night_receive_payment(
  p_receivable uuid,
  p_amount     integer,
  p_memo       text default null
) returns public.night_receivable
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; r public.night_receivable;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into r from public.night_receivable where id = p_receivable;
  if not found then raise exception '売掛が見つかりません'; end if;
  if not app.can_store(r.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_amount <= 0 then raise exception '入金額を入れてください'; end if;
  if p_amount > r.balance then
    raise exception '入金額（%円）が残高（%円）を超えています', p_amount, r.balance;
  end if;

  insert into public.night_receivable_log(tenant_id, receivable_id, kind, amount, memo, created_by)
  values (r.tenant_id, r.id, 'payment', p_amount, p_memo, me.id);

  select * into r from public.night_receivable where id = p_receivable;
  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_open_visit(uuid, text, uuid, text, integer, uuid),
  public.night_add_item(uuid, uuid, integer, uuid),
  public.night_remove_item(uuid),
  public.night_set_discount(uuid, integer),
  public.night_close_visit(uuid, integer, integer, integer, date, text),
  public.night_reopen_visit(uuid),
  public.night_close_day(uuid, date, integer, text),
  public.night_receive_payment(uuid, integer, text)
to authenticated;
