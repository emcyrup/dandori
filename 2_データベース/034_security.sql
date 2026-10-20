-- ============================================================================
--  ナイトだんどり / 不正アクセスの検知（記録と遮断の表）
--  034_security.sql
--
--  貼り付け先： SQL Editor（001 … 033 のあと）。何度流しても壊れません。
--
--  検知そのものは入口（server/gateway/security.mjs）が行い、ここには
--    security_event … 何が起きたか（ログイン失敗の連続、探索アクセス、鍵の不正利用、大量アクセス、遮断）
--    security_block … いま遮断している接続元（IP）。店長が画面から解除できる
--  を残します。入口はサーバー鍵で書き、店長以上が画面で読みます。
--  店舗ごとに別の環境（別の入口・別の DB）なので、表は店舗の環境ごとに独立です。
-- ============================================================================
\set ON_ERROR_STOP on

create table if not exists public.security_event (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  kind        text not null,            -- login_fail / login_bruteforce / scan / bad_token / svc_key_misuse / flood / blocked / unblocked
  severity    text not null default 'warn',   -- info / warn / high
  ip          text,
  path        text,
  user_email  text,
  detail      jsonb not null default '{}'::jsonb,
  blocked_until timestamptz
);
create index if not exists idx_security_event_at on public.security_event(at desc);
create index if not exists idx_security_event_ip on public.security_event(ip, at desc);

create table if not exists public.security_block (
  ip          text primary key,
  reason      text not null,
  blocked_at  timestamptz not null default now(),
  until       timestamptz not null,
  hits        integer not null default 0,
  released    boolean not null default false,
  released_by uuid references public.staff(id) on delete set null,
  released_at timestamptz,
  note        text
);

alter table public.security_event enable row level security;
alter table public.security_block enable row level security;

-- 店長以上は読める。遮断の解除（released）だけ店長以上が書ける。それ以外はサーバー鍵（入口）だけ
drop policy if exists p_security_event_read on public.security_event;
create policy p_security_event_read on public.security_event
  for select to authenticated using (app.is_boss());

drop policy if exists p_security_block_read on public.security_block;
create policy p_security_block_read on public.security_block
  for select to authenticated using (app.is_boss());

drop policy if exists p_security_block_release on public.security_block;
create policy p_security_block_release on public.security_block
  for update to authenticated using (app.is_boss()) with check (app.is_boss());

-- サーバー鍵（役割ありの環境）。単一ロールモードでは post-single.sql が同じ意味の許可を付けます
do $$
begin
  if to_regrole('service_role') is not null then
    execute 'drop policy if exists p_security_event_svc on public.security_event';
    execute 'create policy p_security_event_svc on public.security_event for all to service_role using (true) with check (true)';
    execute 'drop policy if exists p_security_block_svc on public.security_block';
    execute 'create policy p_security_block_svc on public.security_block for all to service_role using (true) with check (true)';
    execute 'grant select, insert, update, delete on public.security_event, public.security_block to service_role';
  end if;
end $$;

grant select on public.security_event to authenticated;
grant select, update on public.security_block to authenticated;
grant usage, select on sequence public.security_event_id_seq to authenticated;

-- 画面用：直近の件数（24時間・7日）と、いま遮断中の数
create or replace function public.security_summary()
returns jsonb
language sql stable security definer set search_path = public, app
as $$
  select case when app.is_boss() then jsonb_build_object(
    'day',   (select count(*) from public.security_event where at > now() - interval '24 hours' and kind <> 'unblocked'),
    'week',  (select count(*) from public.security_event where at > now() - interval '7 days' and kind <> 'unblocked'),
    'high',  (select count(*) from public.security_event where at > now() - interval '7 days' and severity = 'high'),
    'blocked', (select count(*) from public.security_block where not released and until > now())
  ) else null end;
$$;
grant execute on function public.security_summary() to authenticated;

-- 遮断の解除（だれが解除したかを残す）
create or replace function public.security_unblock(p_ip text, p_note text default null)
returns public.security_block
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; b public.security_block;
begin
  select * into me from app.me();
  if me.id is null or not app.is_boss() then raise exception '遮断の解除は、店長以上の方だけができます'; end if;
  update public.security_block
     set released = true, released_by = me.id, released_at = now(), note = coalesce(p_note, note)
   where ip = p_ip
   returning * into b;
  if not found then raise exception 'その接続元は遮断されていません'; end if;
  insert into public.security_event(kind, severity, ip, detail)
  values ('unblocked', 'info', p_ip, jsonb_build_object('by', me.name, 'note', p_note));
  return b;
end;
$$;
grant execute on function public.security_unblock(text, text) to authenticated;

-- 古い記録は 90 日で消す（入口が 1 日 1 回呼ぶ）
create or replace function public.security_prune(p_days integer default 90)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare n integer;
begin
  if not (app.is_boss()
          or current_user = 'service_role'
          or coalesce((current_setting('request.jwt.claims', true))::jsonb ->> 'svc', '') = 'true'
          or coalesce((current_setting('request.jwt.claims', true))::jsonb ->> 'role', '') = 'service_role') then
    raise exception '権限がありません';
  end if;
  delete from public.security_event where at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  delete from public.security_block where released and released_at < now() - interval '30 days';
  return n;
end;
$$;
grant execute on function public.security_prune(integer) to authenticated;

notify pgrst, 'reload schema';
