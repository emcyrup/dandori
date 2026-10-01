-- ============================================================================
--  ナイトだんどり / ボトルキープ台帳
--  012_bottle.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜006、009 を先に実行しておいてください）
--
--  入れたボトルを、お客様ごとに管理します。
--  ・棚番とお客様がひもづく
--  ・残量を「出すたび」に更新できる
--  ・期限が近いものが一覧に出る
--  何度実行しても壊れません。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. 店舗にキープ期間の設定を足す
-- ----------------------------------------------------------------------------
alter table public.store
  add column if not exists bottle_keep_months integer not null default 6;

comment on column public.store.bottle_keep_months is
  'ボトルキープの期間（か月）。登録時の期限の初期値に使います。0なら期限なし。';


-- ----------------------------------------------------------------------------
--  2. ボトル台帳
-- ----------------------------------------------------------------------------
create table if not exists public.night_bottle (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant(id) on delete cascade,
  store_id    uuid not null references public.store(id) on delete cascade,
  customer_id uuid references public.night_customer(id) on delete set null,
  guest_name  text,                       -- 台帳にないお客様のとき
  cast_id     uuid references public.night_cast(id) on delete set null,  -- 入れたときの担当
  visit_id    uuid references public.night_visit(id) on delete set null, -- 入れた伝票
  name        text not null,              -- 銘柄
  kind        text,                       -- 焼酎／ウイスキー／シャンパン など
  location    text,                       -- 棚番・ボトル番号
  opened_on   date not null default current_date,
  expires_on  date,                       -- null は期限なし
  remaining   integer not null default 100 check (remaining between 0 and 100),
  status      text not null default 'keeping',  -- keeping / consumed / expired / disposed
  note        text,
  created_by  uuid references public.staff(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_bottle_store on public.night_bottle(store_id, status);
create index if not exists idx_bottle_cust  on public.night_bottle(customer_id);
create index if not exists idx_bottle_exp   on public.night_bottle(store_id, expires_on)
  where status = 'keeping';

drop trigger if exists trg_touch_night_bottle on public.night_bottle;
create trigger trg_touch_night_bottle before update on public.night_bottle
for each row execute function app.touch_updated_at();


-- ----------------------------------------------------------------------------
--  3. 出し入れの履歴
-- ----------------------------------------------------------------------------
create table if not exists public.night_bottle_log (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  bottle_id     uuid not null references public.night_bottle(id) on delete cascade,
  business_date date not null default current_date,
  action        text not null,            -- keep / serve / extend / consume / dispose / edit
  remaining     integer,                  -- その時点の残量
  visit_id      uuid references public.night_visit(id) on delete set null,
  memo          text,
  created_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_bottlelog on public.night_bottle_log(bottle_id, created_at desc);


-- ----------------------------------------------------------------------------
--  4. RLS
-- ----------------------------------------------------------------------------
alter table public.night_bottle     enable row level security;
alter table public.night_bottle_log enable row level security;

drop policy if exists p_night_bottle on public.night_bottle;
create policy p_night_bottle on public.night_bottle for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id));

drop policy if exists p_night_bottle_log on public.night_bottle_log;
create policy p_night_bottle_log on public.night_bottle_log for all
  using (exists (select 1 from public.night_bottle b
                 where b.id = bottle_id and b.tenant_id = app.my_tenant()
                   and app.can_store(b.store_id)))
  with check (exists (select 1 from public.night_bottle b
                 where b.id = bottle_id and b.tenant_id = app.my_tenant()
                   and app.can_store(b.store_id)));


-- ----------------------------------------------------------------------------
--  5. ボトルを登録する
--     期限は、店舗の設定（既定6か月）から自動で入ります。
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_keep(
  p_store    uuid,
  p_name     text,
  p_customer uuid default null,
  p_guest    text default null,
  p_kind     text default null,
  p_location text default null,
  p_cast     uuid default null,
  p_visit    uuid default null,
  p_months   integer default null,     -- 省略すると店舗の設定
  p_note     text default null
) returns public.night_bottle
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; b public.night_bottle; m integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_name is null or btrim(p_name) = '' then raise exception '銘柄を入れてください'; end if;
  if p_customer is null and (p_guest is null or btrim(p_guest) = '') then
    raise exception 'お客様を選ぶか、お名前を入れてください';
  end if;

  select * into st from public.store where id = p_store;
  m := coalesce(p_months, st.bottle_keep_months);

  insert into public.night_bottle(
    tenant_id, store_id, customer_id, guest_name, cast_id, visit_id,
    name, kind, location, opened_on, expires_on, remaining, status, note, created_by)
  values (
    me.tenant_id, p_store, p_customer, nullif(btrim(coalesce(p_guest,'')), ''),
    p_cast, p_visit, btrim(p_name), p_kind, p_location,
    app.business_date(now(), st.day_cutoff),
    case when m > 0 then app.business_date(now(), st.day_cutoff) + (m || ' months')::interval
         else null end,
    100, 'keeping', p_note, me.id)
  returning * into b;

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action,
                                      remaining, visit_id, memo, created_by)
  values (b.tenant_id, b.id, b.opened_on, 'keep', 100, p_visit, p_note, me.id);

  return b;
end;
$$;


-- ----------------------------------------------------------------------------
--  6. ボトルを出す（残量を更新する）
--     残量が0になると、自動で「飲み切り」になります。
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_serve(
  p_bottle    uuid,
  p_remaining integer,
  p_visit     uuid default null,
  p_memo      text default null
) returns public.night_bottle
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; b public.night_bottle; st public.store; r integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into b from public.night_bottle where id = p_bottle;
  if not found then raise exception 'ボトルが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if b.status <> 'keeping' then raise exception 'このボトルはキープ中ではありません'; end if;

  r := least(greatest(coalesce(p_remaining, b.remaining), 0), 100);
  if r > b.remaining then
    raise exception '残量は増やせません（いまは%%%）。直す場合は「内容を修正」から', b.remaining;
  end if;

  select * into st from public.store where id = b.store_id;

  update public.night_bottle
     set remaining = r,
         status = case when r = 0 then 'consumed' else 'keeping' end
   where id = p_bottle
   returning * into b;

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action,
                                      remaining, visit_id, memo, created_by)
  values (b.tenant_id, b.id, app.business_date(now(), st.day_cutoff),
          case when r = 0 then 'consume' else 'serve' end, r, p_visit, p_memo, me.id);

  return b;
end;
$$;


-- ----------------------------------------------------------------------------
--  7. 状態を変える（期限切れ・廃棄・キープに戻す）
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_status(
  p_bottle uuid, p_status text, p_memo text default null
) returns public.night_bottle
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; b public.night_bottle; st public.store;
begin
  select * into me from app.me();
  if p_status not in ('keeping','consumed','expired','disposed') then
    raise exception '状態の指定が正しくありません';
  end if;
  if p_status in ('disposed','expired') and me.role not in ('owner','manager') then
    raise exception '廃棄・期限切れの処理は、店長以上の権限が必要です';
  end if;

  select * into b from public.night_bottle where id = p_bottle;
  if not found then raise exception 'ボトルが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = b.store_id;

  update public.night_bottle set status = p_status where id = p_bottle returning * into b;

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action,
                                      remaining, memo, created_by)
  values (b.tenant_id, b.id, app.business_date(now(), st.day_cutoff),
          case when p_status = 'disposed' then 'dispose' else p_status end,
          b.remaining, p_memo, me.id);

  return b;
end;
$$;


-- ----------------------------------------------------------------------------
--  8. 期限を延ばす
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_extend(
  p_bottle uuid, p_months integer default 3, p_memo text default null
) returns public.night_bottle
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; b public.night_bottle; st public.store;
begin
  select * into me from app.me();
  select * into b from public.night_bottle where id = p_bottle;
  if not found then raise exception 'ボトルが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = b.store_id;

  update public.night_bottle
     set expires_on = coalesce(expires_on, app.business_date(now(), st.day_cutoff))
                      + (greatest(p_months,1) || ' months')::interval,
         status = case when status = 'expired' then 'keeping' else status end
   where id = p_bottle
   returning * into b;

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action,
                                      remaining, memo, created_by)
  values (b.tenant_id, b.id, app.business_date(now(), st.day_cutoff), 'extend',
          b.remaining, p_memo, me.id);

  return b;
end;
$$;


-- ----------------------------------------------------------------------------
--  9. 内容を修正する（銘柄・棚番・残量・期限の直し）
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_edit(
  p_bottle    uuid,
  p_name      text default null,
  p_kind      text default null,
  p_location  text default null,
  p_remaining integer default null,
  p_expires   date default null,
  p_note      text default null
) returns public.night_bottle
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; b public.night_bottle; st public.store;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception 'ボトルの修正は、店長以上の権限が必要です';
  end if;

  select * into b from public.night_bottle where id = p_bottle;
  if not found then raise exception 'ボトルが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = b.store_id;

  update public.night_bottle
     set name       = coalesce(nullif(btrim(coalesce(p_name,'')), ''), name),
         kind       = coalesce(p_kind, kind),
         location   = coalesce(p_location, location),
         remaining  = coalesce(least(greatest(p_remaining,0),100), remaining),
         expires_on = coalesce(p_expires, expires_on),
         note       = coalesce(p_note, note)
   where id = p_bottle
   returning * into b;

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action,
                                      remaining, memo, created_by)
  values (b.tenant_id, b.id, app.business_date(now(), st.day_cutoff), 'edit',
          b.remaining, p_memo_safe(p_note), me.id);

  return b;
end;
$$;

-- メモが null でもログが書けるようにする小さな補助
create or replace function public.p_memo_safe(p text)
returns text language sql immutable as $$ select coalesce(p, '内容を修正') $$;


-- ----------------------------------------------------------------------------
--  10. 一覧（キープ中・期限が近い・お客様ごと）
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_list(
  p_store    uuid,
  p_status   text default 'keeping',   -- keeping / all / expired など
  p_customer uuid default null
) returns table (
  id           uuid,
  customer_id  uuid,
  who          text,
  cast_name    text,
  name         text,
  kind         text,
  location     text,
  opened_on    date,
  expires_on   date,
  days_left    integer,
  remaining    integer,
  status       text,
  note         text,
  last_served  date
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select b.id, b.customer_id,
         coalesce(cu.name, b.guest_name, '（お名前なし）'),
         ca.name, b.name, b.kind, b.location, b.opened_on, b.expires_on,
         case when b.expires_on is null then null
              else (b.expires_on - current_date)::integer end,
         b.remaining, b.status, b.note,
         (select max(l.business_date) from public.night_bottle_log l
           where l.bottle_id = b.id and l.action in ('serve','consume'))
    from public.night_bottle b
    left join public.night_customer cu on cu.id = b.customer_id
    left join public.night_cast ca     on ca.id = b.cast_id
   where b.store_id = p_store
     and (p_status = 'all' or b.status = p_status)
     and (p_customer is null or b.customer_id = p_customer)
   order by
     case when b.status = 'keeping' then 0 else 1 end,
     b.expires_on nulls last, b.opened_on;
end;
$$;


-- ----------------------------------------------------------------------------
--  11. その日の締め用のまとめ（新規◯本・期限が近い◯本）
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_summary(
  p_store uuid, p_date date default null, p_soon_days integer default 30
) returns table (
  kept_today   integer,
  served_today integer,
  keeping      integer,
  expiring     integer,
  expired      integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare st public.store; bd date;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  bd := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  return query
  select
    (select count(*)::integer from public.night_bottle
      where store_id = p_store and opened_on = bd),
    (select count(distinct l.bottle_id)::integer from public.night_bottle_log l
       join public.night_bottle b2 on b2.id = l.bottle_id
      where b2.store_id = p_store and l.business_date = bd
        and l.action in ('serve','consume')),
    (select count(*)::integer from public.night_bottle
      where store_id = p_store and status = 'keeping'),
    (select count(*)::integer from public.night_bottle
      where store_id = p_store and status = 'keeping'
        and expires_on is not null
        and expires_on between current_date and current_date + p_soon_days),
    (select count(*)::integer from public.night_bottle
      where store_id = p_store and status = 'keeping'
        and expires_on is not null and expires_on < current_date);
end;
$$;


-- ----------------------------------------------------------------------------
--  12. 期限切れの一括処理（店長以上）
-- ----------------------------------------------------------------------------
create or replace function public.night_bottle_mark_expired(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; n integer;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception 'この操作は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.night_bottle
     set status = 'expired'
   where store_id = p_store and status = 'keeping'
     and expires_on is not null and expires_on < current_date;
  get diagnostics n = row_count;
  return n;
end;
$$;


-- ----------------------------------------------------------------------------
--  13. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_bottle_keep(uuid, text, uuid, text, text, text, uuid, uuid, integer, text),
  public.night_bottle_serve(uuid, integer, uuid, text),
  public.night_bottle_status(uuid, text, text),
  public.night_bottle_extend(uuid, integer, text),
  public.night_bottle_edit(uuid, text, text, text, integer, date, text),
  public.night_bottle_list(uuid, text, uuid),
  public.night_bottle_summary(uuid, date, integer),
  public.night_bottle_mark_expired(uuid),
  public.p_memo_safe(text)
to authenticated;


-- ============================================================================
--  デモ用：キープ中のボトルを4本
-- ============================================================================
do $$
declare
  t_id uuid; s_id uuid; bd date;
  cu_sato uuid; cu_ito uuid; cu_taka uuid;
  c_aya uuid; c_min uuid;
begin
  select id into s_id from public.store where name = '三宮本店' limit 1;
  if s_id is null then return; end if;
  select tenant_id into t_id from public.store where id = s_id;
  if exists (select 1 from public.night_bottle where store_id = s_id) then return; end if;

  update public.store set bottle_keep_months = 6 where id = s_id;

  select id into cu_sato from public.night_customer where store_id = s_id and name = '佐藤様';
  select id into cu_ito  from public.night_customer where store_id = s_id and name = '伊藤様';
  select id into cu_taka from public.night_customer where store_id = s_id and name = '高橋様';
  select id into c_aya   from public.night_cast where store_id = s_id and name = 'あや';
  select id into c_min   from public.night_cast where store_id = s_id and name = 'みなみ';
  select app.business_date(now(), day_cutoff) into bd from public.store where id = s_id;

  insert into public.night_bottle(tenant_id, store_id, customer_id, cast_id, name, kind,
                                  location, opened_on, expires_on, remaining, status)
  values
    (t_id, s_id, cu_sato, c_aya, '黒霧島（一升）', '焼酎', 'A-12',
     bd - 40, bd + 140, 50, 'keeping'),
    (t_id, s_id, cu_ito,  c_min, '響 JAPANESE HARMONY', 'ウイスキー', 'B-03',
     bd - 150, bd + 30, 75, 'keeping'),
    (t_id, s_id, cu_taka, c_aya, '佐藤 黒', '焼酎', 'A-07',
     bd - 170, bd + 10, 25, 'keeping'),
    (t_id, s_id, cu_sato, c_aya, '山崎12年', 'ウイスキー', 'B-11',
     bd - 200, bd - 20, 60, 'keeping');

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action, remaining)
  select t_id, id, opened_on, 'keep', 100 from public.night_bottle where store_id = s_id;

  insert into public.night_bottle_log(tenant_id, bottle_id, business_date, action, remaining)
  select t_id, id, bd - 3, 'serve', remaining from public.night_bottle
   where store_id = s_id and location in ('A-12','B-03');
end $$;


-- ============================================================================
--  確認用
--   select who, name, location, remaining, days_left, status
--     from public.night_bottle_list((select id from store where name='三宮本店'));
--   select * from public.night_bottle_summary((select id from store where name='三宮本店'));
-- ============================================================================
