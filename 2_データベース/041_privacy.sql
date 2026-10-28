-- ============================================================================
--  ナイトだんどり / 売上の数字とキャストの個人情報を、店長だけに（2026-10-28）
--  041_privacy.sql
--
--  貼り付け先： SQL Editor（001 … 040 のあと）。何度流しても壊れません。
--
--   1. 売上の集計（night_sales_*）は、店長か、設定 → 権限 で「売上」を許可されたスタッフだけ。
--      その日の伝票の詳細（締め・日報で使う）は、「締め・日報」か「売上」を使える人だけ
--      （いままでは画面を出していないだけで、データとしてはスタッフも呼べた）
--   2. キャストの個人情報（本名・生年月日・住所・電話・緊急連絡先）を別の表 night_cast_private に移し、
--      店長と本人だけが読めるようにする。単一ロールモードでは列ごとに隠せないため、表を分ける。
--      night_cast にこれらを書いても（取り込み・古い画面など）、自動で night_cast_private へ移る
-- ============================================================================
\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
--  0. その機能を使えるか（設定 → 権限。perm.js の一覧と同じ既定）
-- ----------------------------------------------------------------------------
create or replace function app.can_feature(p_key text, p_staff_default boolean)
returns boolean
language plpgsql stable security definer set search_path = public, app
as $$
declare me public.staff; v jsonb;
begin
  -- サーバーの中・運用スクリプトからは通す
  if app.is_service() then return true; end if;
  if to_regprocedure('app.is_local()') is not null and app.is_local() then return true; end if;
  select * into me from app.me();
  if me.id is null then return false; end if;
  if me.role in ('owner', 'manager') then return true; end if;
  select role_features -> 'staff' -> p_key into v from public.tenant where id = me.tenant_id;
  if v is null or jsonb_typeof(v) <> 'boolean' then return p_staff_default; end if;
  return v::text = 'true';
end;
$$;

-- 関数にふたを付ける（中身は app.<名前>_core041 に移し、public には確かめてから呼ぶ薄い入口を置く）。
-- 008・033・038 を流し直して public 側がふた無しに戻っても、もう一度流せば付け直す
create or replace function app.guard_feature(p_sig text, p_cond text, p_msg text)
returns text
language plpgsql
as $$
declare o oid; v_name text; v_args text; v_types text; v_names text; v_ret text; v_vol text; v_core text; v_body text;
begin
  o := to_regprocedure(p_sig);
  if o is null then return 'とばしました（ありません）: ' || p_sig; end if;
  if position('guard041' in (select prosrc from pg_proc where oid = o)) > 0 then return 'そのまま: ' || p_sig; end if;

  select p.proname, pg_get_function_arguments(o), pg_get_function_result(o),
         case p.provolatile when 'i' then 'immutable' when 's' then 'stable' else 'volatile' end,
         coalesce(array_to_string(p.proargnames[1:p.pronargs], ', '), '')
    into v_name, v_args, v_ret, v_vol, v_names
    from pg_proc p where p.oid = o;
  select coalesce(string_agg(format_type(t, null), ',' order by ord), '') into v_types
    from pg_proc p, unnest(p.proargtypes) with ordinality as u(t, ord) where p.oid = o;

  v_core := v_name || '_core041';
  if to_regprocedure('app.' || quote_ident(v_core) || '(' || v_types || ')') is not null then
    execute format('drop function app.%I(%s)', v_core, v_types);
  end if;
  execute format('alter function %s set schema app', p_sig);
  execute format('alter function app.%I(%s) rename to %I', v_name, v_types, v_core);

  if v_ret like 'TABLE(%' or v_ret like 'SETOF %' then
    v_body := format(E'begin  -- guard041\n  if not (%s) then raise exception %L; end if;\n  return query select * from app.%I(%s);\nend;',
                     p_cond, p_msg, v_core, v_names);
  else
    v_body := format(E'begin  -- guard041\n  if not (%s) then raise exception %L; end if;\n  return app.%I(%s);\nend;',
                     p_cond, p_msg, v_core, v_names);
  end if;
  execute format('create or replace function public.%I(%s) returns %s language plpgsql %s security definer set search_path = public, app as %L',
                 v_name, v_args, v_ret, v_vol, v_body);
  execute format('grant execute on function public.%I(%s) to authenticated', v_name, v_types);
  return 'ふたを付けました: ' || p_sig;
end;
$$;
revoke all on function app.guard_feature(text, text, text) from public;

-- ----------------------------------------------------------------------------
--  1. 売上の集計
-- ----------------------------------------------------------------------------
do $$
declare r text;
begin
  foreach r in array array[
    'public.night_sales_today(uuid)',
    'public.night_sales_daily(uuid,date,date)',
    'public.night_sales_category(uuid,date,date)',
    'public.night_sales_cast(uuid,date,date)',
    'public.night_sales_customer(uuid,date,date,integer)'
  ] loop
    raise notice '%', app.guard_feature(r, $c$app.can_feature('sales.html', false)$c$,
      '売上は、店長（または設定 → 権限 で「売上」を許可された方）だけが見られます');
  end loop;
  raise notice '%', app.guard_feature('public.night_sales_visits(uuid,date)',
    $c$app.can_feature('sales.html', false) or app.can_feature('close.html', true)$c$,
    'その日の伝票は、「締め・日報」か「売上」を使える方だけが見られます');
end $$;

-- ----------------------------------------------------------------------------
--  2. キャストの個人情報
-- ----------------------------------------------------------------------------
create table if not exists public.night_cast_private (
  cast_id         uuid primary key references public.night_cast(id) on delete cascade deferrable initially deferred,
  tenant_id       uuid not null references public.tenant(id) on delete cascade,
  store_id        uuid not null references public.store(id) on delete cascade,
  real_name       text,
  birth_date      date,
  address         text,
  phone           text,
  emergency_name  text,
  emergency_phone text,
  updated_at      timestamptz not null default now()
);
alter table public.night_cast_private enable row level security;

drop policy if exists p_night_cast_private_sel on public.night_cast_private;
create policy p_night_cast_private_sel on public.night_cast_private for select to authenticated
  using (tenant_id = app.my_tenant() and app.can_store(store_id)
         and (app.is_boss() or exists (select 1 from app.my_subject() m
                                        where m.subject_kind = 'night_cast' and m.subject_id = cast_id)));
drop policy if exists p_night_cast_private_wr on public.night_cast_private;
create policy p_night_cast_private_wr on public.night_cast_private for all to authenticated
  using (tenant_id = app.my_tenant() and app.can_store(store_id) and app.is_boss())
  with check (tenant_id = app.my_tenant() and app.can_store(store_id) and app.is_boss());
grant select, insert, update, delete on public.night_cast_private to authenticated;

-- night_cast に個人情報が書かれたら、night_cast_private へ移して、night_cast 側は空にする
-- （生年月日の 18 歳チェック trg_cast_age_guard は、名前の順でこれより先に動く）
create or replace function app.trg_cast_zprivate()
returns trigger
language plpgsql security definer set search_path = public, app
as $$
begin
  if new.real_name is null and new.birth_date is null and new.address is null and new.phone is null
     and new.emergency_name is null and new.emergency_phone is null then
    return new;
  end if;
  insert into public.night_cast_private as p(cast_id, tenant_id, store_id, real_name, birth_date, address, phone,
                                             emergency_name, emergency_phone, updated_at)
  values (new.id, new.tenant_id, new.store_id, new.real_name, new.birth_date, new.address, new.phone,
          new.emergency_name, new.emergency_phone, now())
  on conflict (cast_id) do update set
    real_name       = coalesce(excluded.real_name, p.real_name),
    birth_date      = coalesce(excluded.birth_date, p.birth_date),
    address         = coalesce(excluded.address, p.address),
    phone           = coalesce(excluded.phone, p.phone),
    emergency_name  = coalesce(excluded.emergency_name, p.emergency_name),
    emergency_phone = coalesce(excluded.emergency_phone, p.emergency_phone),
    store_id        = excluded.store_id,
    updated_at      = now();
  new.real_name := null; new.birth_date := null; new.address := null; new.phone := null;
  new.emergency_name := null; new.emergency_phone := null;
  return new;
end;
$$;
drop trigger if exists trg_cast_zprivate on public.night_cast;
create trigger trg_cast_zprivate before insert or update on public.night_cast
  for each row execute function app.trg_cast_zprivate();

-- 生年月日の 18 歳チェックは、night_cast_private に直接書いたときも
create or replace function app.trg_cast_private_age()
returns trigger language plpgsql as $$
declare a integer; j date;
begin
  if new.birth_date is null then return new; end if;
  select joined_on into j from public.night_cast where id = new.cast_id;
  a := app.age_on(new.birth_date, coalesce(j, current_date));
  if a < 18 then raise exception '18歳未満の方は登録できません（雇入日時点で%歳）', a; end if;
  return new;
end;
$$;
drop trigger if exists trg_cast_private_age on public.night_cast_private;
create trigger trg_cast_private_age before insert or update of birth_date on public.night_cast_private
  for each row execute function app.trg_cast_private_age();

-- いまある個人情報を移す（トリガが night_cast 側を空にする）
update public.night_cast set real_name = real_name
 where real_name is not null or birth_date is not null or address is not null or phone is not null
    or emergency_name is not null or emergency_phone is not null;

-- 従業者名簿のビュー：個人情報は night_cast_private から（店長と本人以外には空で見える）
drop view if exists public.v_employee_roster;
create view public.v_employee_roster with (security_invoker = on) as
select
  c.id                              as cast_id,
  c.store_id,
  s.name                            as store_name,
  c.name                            as display_name,
  pv.real_name,
  pv.birth_date,
  app.age_on(pv.birth_date)         as age,
  pv.address,
  pv.phone,
  pv.emergency_name,
  pv.emergency_phone,
  c.job_type,
  c.joined_on,
  c.left_on,
  c.left_reason,
  c.is_active,
  ck.checked_on                     as id_checked_on,
  ck.doc_type                       as id_doc_type,
  ck.method                         as id_method,
  (pv.real_name is null or pv.birth_date is null or pv.address is null
   or pv.phone is null or c.joined_on is null)             as roster_incomplete,
  (ck.id is null)                                          as id_check_missing,
  (app.age_on(pv.birth_date) is not null and app.age_on(pv.birth_date) < 20) as under_20
from public.night_cast c
join public.store s on s.id = c.store_id
left join public.night_cast_private pv on pv.cast_id = c.id
left join lateral (
  select * from public.night_id_check k
   where k.cast_id = c.id
   order by k.checked_on desc, k.created_at desc
   limit 1
) ck on true;
grant select on public.v_employee_roster to authenticated;

-- 本人確認の記録：生年月日は night_cast_private から
create or replace function public.night_id_check_add(
  p_cast uuid, p_doc_type text, p_method text default 'original',
  p_on date default current_date, p_note text default null
) returns public.night_id_check
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; b date; r public.night_id_check;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.is_boss() then raise exception '本人確認の記録は、店長の権限が必要です'; end if;
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select birth_date into b from public.night_cast_private where cast_id = c.id;
  if b is null then raise exception '先に生年月日を登録してください'; end if;

  insert into public.night_id_check(
    tenant_id, store_id, cast_id, checked_on, doc_type, method, age_at_check, checked_by, note)
  values (c.tenant_id, c.store_id, c.id, p_on, p_doc_type, p_method, app.age_on(b, p_on), me.id, p_note)
  returning * into r;
  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (c.tenant_id, c.store_id, me.id, 'id_check', 'night_id_check', r.id::text,
          jsonb_build_object('cast', c.name, 'doc', p_doc_type, 'age', r.age_at_check));
  return r;
end;
$$;

notify pgrst, 'reload schema';
