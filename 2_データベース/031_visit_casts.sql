-- ============================================================================
--  ナイトだんどり / 卓についているキャスト（複数）と、注文ごとのバック先
--  031_visit_casts.sql
--
--  1つの卓に何人ものキャストがつくことがあるので、
--  「この卓にいま誰がついているか」を複数登録できるようにします。
--  バックが付く注文（ドリンク・ボトルなど）を打つときは、画面で
--  「誰にバックを付けますか？」と、ついているキャストの中から選びます。
--  何度流しても壊れません。
-- ============================================================================

create table if not exists public.night_visit_cast (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenant(id) on delete cascade,
  store_id   uuid not null references public.store(id) on delete cascade,
  visit_id   uuid not null references public.night_visit(id) on delete cascade,
  cast_id    uuid not null references public.night_cast(id) on delete cascade,
  seated_at  timestamptz not null default now(),
  seated_by  uuid references public.staff(id) on delete set null,
  unique (visit_id, cast_id)
);
create index if not exists idx_visit_cast_visit on public.night_visit_cast(visit_id);

alter table public.night_visit_cast enable row level security;
drop policy if exists p_night_visit_cast on public.night_visit_cast;
create policy p_night_visit_cast on public.night_visit_cast for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id));
grant select, insert, update, delete on public.night_visit_cast to authenticated;


-- ---- 卓にキャストを付ける
create or replace function public.night_visit_cast_add(p_visit uuid, p_cast uuid)
returns public.night_visit_cast
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; v public.night_visit; c public.night_cast; r public.night_visit_cast;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if v.status <> 'open' then raise exception 'この伝票は締め済みです'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into c from public.night_cast where id = p_cast and store_id = v.store_id and is_active;
  if not found then raise exception 'キャストが見つかりません'; end if;

  insert into public.night_visit_cast(tenant_id, store_id, visit_id, cast_id, seated_by)
  values (v.tenant_id, v.store_id, v.id, p_cast, me.id)
  on conflict (visit_id, cast_id) do update set seated_at = now()
  returning * into r;

  -- 担当がまだ無い卓なら、最初についた人を担当にしておく（フリーの割り振り）
  if v.main_cast_id is null then
    update public.night_visit set main_cast_id = p_cast, updated_at = now() where id = v.id;
  end if;
  return r;
end;
$$;

-- ---- 卓からキャストを外す
create or replace function public.night_visit_cast_remove(p_visit uuid, p_cast uuid)
returns void
language plpgsql security definer set search_path = public, app
as $$
declare v public.night_visit;
begin
  if (select id from app.me()) is null then raise exception 'ログインが必要です'; end if;
  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if v.status <> 'open' then raise exception 'この伝票は締め済みです'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  delete from public.night_visit_cast where visit_id = p_visit and cast_id = p_cast;
  -- 外した人が担当だったら、残っている人の先頭を担当にする（誰もいなければフリー）
  if v.main_cast_id = p_cast then
    update public.night_visit
       set main_cast_id = (select vc.cast_id from public.night_visit_cast vc
                            where vc.visit_id = p_visit order by vc.seated_at limit 1),
           updated_at = now()
     where id = p_visit;
  end if;
end;
$$;

grant execute on function public.night_visit_cast_add(uuid, uuid)    to authenticated;
grant execute on function public.night_visit_cast_remove(uuid, uuid) to authenticated;


-- ---- ホールの一覧に「ついているキャスト」を足す
drop view if exists public.v_open_visit;
create view public.v_open_visit with (security_invoker = on) as
select v.id, v.store_id, v.business_date, v.table_no, v.head_count,
       coalesce(c.name, v.guest_name) as guest,
       ca.name as main_cast,
       v.entered_at,
       extract(epoch from (now() - v.entered_at))::integer / 60 as minutes,
       v.subtotal, v.service_charge, v.tax, v.total,
       (select string_agg(x.name, '・' order by vc.seated_at)
          from public.night_visit_cast vc
          join public.night_cast x on x.id = vc.cast_id
         where vc.visit_id = v.id) as casts
from public.night_visit v
left join public.night_customer c on c.id = v.customer_id
left join public.night_cast ca on ca.id = v.main_cast_id
where v.status = 'open';
grant select on public.v_open_visit to authenticated;


-- ---- 注文の登録：「バックなしで打つ」に対応
--      p_cast に 00000000-0000-0000-0000-000000000000 を渡すと、
--      担当がいてもバックを付けずに登録します（002 の同じ関数を差し替え）。
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
  v_cast   uuid;
  v_noback boolean := (p_cast = '00000000-0000-0000-0000-000000000000'::uuid);
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

  -- バック先：指定があればその人。無ければ、バックが出る注文に限り卓の担当。「バックなし」なら誰にも付けない
  v_cast := case when v_noback then null
                 else coalesce(p_cast, case when v_back > 0 then v.main_cast_id else null end) end;
  if v_cast is not null and not exists (
       select 1 from public.night_cast where id = v_cast and store_id = v.store_id) then
    raise exception 'キャストが見つかりません';
  end if;

  insert into public.night_visit_item(
    tenant_id, store_id, visit_id, menu_id, category, name,
    unit_price, quantity, amount, cast_id, back_amount,
    service_apply, tax_apply, punched_at, punched_by)
  values (
    v.tenant_id, v.store_id, v.id, m.id, m.category, m.name,
    m.unit_price, v_qty, v_amount,
    v_cast,
    case when v_cast is null then 0 else v_back end,
    m.service_apply, m.tax_apply, now(), me.id)
  returning * into it;

  return it;
end;
$$;


-- ---- 卓を開くときに選んだキャストも、「ついているキャスト」に入れておく
create or replace function app.trg_visit_seat_main_cast()
returns trigger language plpgsql security definer set search_path = public, app
as $$
begin
  if new.main_cast_id is not null and new.status = 'open' then
    insert into public.night_visit_cast(tenant_id, store_id, visit_id, cast_id)
    values (new.tenant_id, new.store_id, new.id, new.main_cast_id)
    on conflict (visit_id, cast_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_visit_seat_main_cast on public.night_visit;
create trigger trg_visit_seat_main_cast
  after insert on public.night_visit
  for each row execute function app.trg_visit_seat_main_cast();
