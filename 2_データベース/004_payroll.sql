-- ============================================================================
--  ナイトだんどり / キャスト・給与パック
--  004_payroll.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001 → 002 → 003 を先に実行しておいてください）
--
--  伝票側で1明細ずつ記録してあるバックを、そのまま給与の材料にします。
--  何度実行しても壊れません。
--
--  ※ 重要：控除・罰金・時給の設定は、店舗ごとに慣行が異なります。
--    この仕組みは「入力された条件どおりに計算する」だけで、
--    その条件が適法かどうかの判断はしません。社労士の確認を前提にしてください。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  店舗に最低賃金の設定を足す（下回ったら警告を出すためだけに使います）
-- ----------------------------------------------------------------------------
alter table public.store
  add column if not exists min_wage integer not null default 0;

comment on column public.store.min_wage is
  '地域の最低賃金（円/時）。給与計算のときに下回ると警告を出します。0なら判定しません。';


-- ----------------------------------------------------------------------------
--  日払い
-- ----------------------------------------------------------------------------
create table if not exists public.night_payout (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  cast_id       uuid not null references public.night_cast(id) on delete cascade,
  business_date date not null,
  amount        integer not null,
  memo          text,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.staff(id) on delete set null
);
create index if not exists idx_payout_cast on public.night_payout(cast_id, business_date desc);


-- ----------------------------------------------------------------------------
--  手当・控除
--    kind = 'allowance'（手当・支給）／ 'deduction'（控除）
-- ----------------------------------------------------------------------------
create table if not exists public.night_adjustment (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  cast_id       uuid not null references public.night_cast(id) on delete cascade,
  business_date date not null,
  kind          text not null check (kind in ('allowance','deduction')),
  name          text not null,
  amount        integer not null check (amount >= 0),
  memo          text,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.staff(id) on delete set null
);
create index if not exists idx_adj_cast on public.night_adjustment(cast_id, business_date desc);


-- ----------------------------------------------------------------------------
--  給与の確定（期間ごとに1本）
-- ----------------------------------------------------------------------------
create table if not exists public.night_payroll (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenant(id) on delete cascade,
  store_id       uuid not null references public.store(id) on delete cascade,
  cast_id        uuid not null references public.night_cast(id) on delete cascade,
  period_from    date not null,
  period_to      date not null,
  work_minutes   integer not null default 0,
  hourly_applied integer not null default 0,     -- 実際に適用された時給
  wage_amount    integer not null default 0,     -- 時給ぶん
  back_amount    integer not null default 0,     -- バック合計
  allowance      integer not null default 0,     -- 手当
  deduction      integer not null default 0,     -- 控除
  advance        integer not null default 0,     -- 日払い済み
  net_amount     integer not null default 0,     -- 差引支給額
  nominations    integer not null default 0,
  douhans        integer not null default 0,
  status         text not null default 'confirmed',  -- confirmed / paid
  note           text,
  confirmed_by   uuid references public.staff(id) on delete set null,
  confirmed_at   timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (cast_id, period_from, period_to)
);
create index if not exists idx_payroll_store on public.night_payroll(store_id, period_to desc);

drop trigger if exists trg_touch_night_payroll on public.night_payroll;
create trigger trg_touch_night_payroll before update on public.night_payroll
for each row execute function app.touch_updated_at();


-- ----------------------------------------------------------------------------
--  RLS
-- ----------------------------------------------------------------------------
alter table public.night_payout     enable row level security;
alter table public.night_adjustment enable row level security;
alter table public.night_payroll    enable row level security;

do $$
declare t text;
begin
  foreach t in array array['night_payout','night_adjustment','night_payroll'] loop
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format(
      'create policy p_%1$s on public.%1$s for all
         using (tenant_id = app.my_tenant() and app.can_store(store_id))
         with check (tenant_id = app.my_tenant() and app.can_store(store_id))', t);
  end loop;
end $$;


-- ----------------------------------------------------------------------------
--  出勤・退勤
-- ----------------------------------------------------------------------------
create or replace function public.night_clock_in(
  p_cast uuid,
  p_at   timestamptz default now()
) returns public.night_attendance
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; st public.store; a public.night_attendance; bd date;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = c.store_id;
  bd := app.business_date(p_at, st.day_cutoff);

  insert into public.night_attendance(tenant_id, store_id, cast_id, business_date, clock_in)
  values (c.tenant_id, c.store_id, c.id, bd, p_at)
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
declare me public.staff; c public.night_cast; st public.store; a public.night_attendance; bd date;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = c.store_id;
  bd := app.business_date(p_at, st.day_cutoff);

  update public.night_attendance
     set clock_out = p_at
   where cast_id = p_cast and business_date = bd
   returning * into a;

  if not found then
    raise exception '出勤の記録がありません。先に出勤を押してください';
  end if;
  if a.clock_in is not null and p_at < a.clock_in then
    raise exception '退勤時刻が出勤時刻より前になっています';
  end if;

  return a;
end;
$$;


-- ----------------------------------------------------------------------------
--  日払い・手当・控除を記録する
-- ----------------------------------------------------------------------------
create or replace function public.night_payout_add(
  p_cast uuid, p_date date, p_amount integer, p_memo text default null
) returns public.night_payout
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; r public.night_payout;
begin
  select * into me from app.me();
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_amount <= 0 then raise exception '金額を入れてください'; end if;

  insert into public.night_payout(tenant_id, store_id, cast_id, business_date, amount, memo, created_by)
  values (c.tenant_id, c.store_id, c.id, p_date, p_amount, p_memo, me.id)
  returning * into r;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (c.tenant_id, c.store_id, me.id, 'payout', 'night_payout', r.id::text,
          jsonb_build_object('cast', c.name, 'amount', p_amount));
  return r;
end;
$$;

create or replace function public.night_adjust_add(
  p_cast uuid, p_date date, p_kind text, p_name text,
  p_amount integer, p_memo text default null
) returns public.night_adjustment
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; r public.night_adjustment;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '手当・控除の登録は、店長以上の権限が必要です';
  end if;
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  insert into public.night_adjustment(tenant_id, store_id, cast_id, business_date, kind, name, amount, memo, created_by)
  values (c.tenant_id, c.store_id, c.id, p_date, p_kind, p_name, greatest(p_amount,0), p_memo, me.id)
  returning * into r;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (c.tenant_id, c.store_id, me.id, p_kind, 'night_adjustment', r.id::text,
          jsonb_build_object('cast', c.name, 'name', p_name, 'amount', p_amount));
  return r;
end;
$$;


-- ----------------------------------------------------------------------------
--  時給スライドの判定
--    wage_rules の例：
--      [{"type":"nomination","from":10,"wage":3000},
--       {"type":"sales","from":300000,"wage":3500}]
--    条件を満たすもののうち、いちばん高い時給を採用します。
--    どれも満たさなければ基本時給。
-- ----------------------------------------------------------------------------
create or replace function app.wage_for(
  p_cast uuid, p_nominations integer, p_sales integer
) returns integer
language plpgsql stable security definer set search_path = public, app
as $$
declare c public.night_cast; rule jsonb; best integer;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then return 0; end if;
  best := c.hourly_wage;

  for rule in select * from jsonb_array_elements(coalesce(c.wage_rules, '[]'::jsonb)) loop
    if (rule->>'type') = 'nomination'
       and p_nominations >= coalesce((rule->>'from')::integer, 0) then
      best := greatest(best, coalesce((rule->>'wage')::integer, 0));
    elsif (rule->>'type') = 'sales'
       and p_sales >= coalesce((rule->>'from')::integer, 0) then
      best := greatest(best, coalesce((rule->>'wage')::integer, 0));
    end if;
  end loop;

  return best;
end;
$$;


-- ----------------------------------------------------------------------------
--  給与の試算（保存しません。画面に出すためのもの）
--    期間を指定すると、その期間のキャスト全員ぶんを返します。
-- ----------------------------------------------------------------------------
create or replace function public.night_payroll_preview(
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
  confirmed      boolean
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
           app.wage_for(b.id, b.noms, b.sales) as hourly
      from base b
  )
  select c.id, c.name, c.minutes, c.days, c.late,
         c.noms, c.dous, c.drks, c.sales,
         c.hourly_wage,
         c.hourly,
         (round(c.minutes / 60.0 * c.hourly))::integer as wage_amount,
         c.back,
         c.allw,
         c.dedu,
         c.adv,
         ((round(c.minutes / 60.0 * c.hourly))::integer + c.back + c.allw - c.dedu - c.adv)::integer,
         (st.min_wage > 0 and c.hourly < st.min_wage),
         exists (select 1 from public.night_payroll pr
                  where pr.cast_id = c.id and pr.period_from = p_from and pr.period_to = p_to)
    from calc c
   order by c.name;
end;
$$;


-- ----------------------------------------------------------------------------
--  給与を確定する（試算の結果をそのまま保存します）
-- ----------------------------------------------------------------------------
create or replace function public.night_payroll_confirm(
  p_store uuid, p_from date, p_to date, p_cast uuid default null
) returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; r record; n integer := 0;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '給与の確定は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  for r in select * from public.night_payroll_preview(p_store, p_from, p_to)
            where (p_cast is null or cast_id = p_cast)
  loop
    insert into public.night_payroll(
      tenant_id, store_id, cast_id, period_from, period_to,
      work_minutes, hourly_applied, wage_amount, back_amount,
      allowance, deduction, advance, net_amount, nominations, douhans,
      confirmed_by, confirmed_at)
    values (
      me.tenant_id, p_store, r.cast_id, p_from, p_to,
      r.work_minutes, r.hourly_applied, r.wage_amount, r.back_amount,
      r.allowance, r.deduction, r.advance, r.net_amount, r.nominations, r.douhans,
      me.id, now())
    on conflict (cast_id, period_from, period_to) do update
      set work_minutes = excluded.work_minutes,
          hourly_applied = excluded.hourly_applied,
          wage_amount = excluded.wage_amount,
          back_amount = excluded.back_amount,
          allowance = excluded.allowance,
          deduction = excluded.deduction,
          advance = excluded.advance,
          net_amount = excluded.net_amount,
          nominations = excluded.nominations,
          douhans = excluded.douhans,
          confirmed_by = excluded.confirmed_by,
          confirmed_at = now();
    n := n + 1;
  end loop;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, p_store, me.id, 'payroll_confirm', 'night_payroll', null,
          jsonb_build_object('from', p_from, 'to', p_to, 'count', n));

  return n;
end;
$$;


-- ----------------------------------------------------------------------------
--  権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_clock_in(uuid, timestamptz),
  public.night_clock_out(uuid, timestamptz),
  public.night_payout_add(uuid, date, integer, text),
  public.night_adjust_add(uuid, date, text, text, integer, text),
  public.night_payroll_preview(uuid, date, date),
  public.night_payroll_confirm(uuid, date, date, uuid),
  app.wage_for(uuid, integer, integer)
to authenticated;


-- ============================================================================
--  デモ用：時給スライドと最低賃金を入れておきます
-- ============================================================================
do $$
declare s uuid;
begin
  select id into s from public.store where name = '三宮本店' limit 1;
  if s is null then return; end if;

  update public.store set min_wage = 1052 where id = s and min_wage = 0;

  -- あや：本指名10本以上で時給3,000円、売上30万以上で3,500円
  update public.night_cast
     set wage_rules = '[{"type":"nomination","from":10,"wage":3000},
                        {"type":"sales","from":300000,"wage":3500}]'::jsonb
   where store_id = s and name = 'あや' and wage_rules = '[]'::jsonb;
end $$;
