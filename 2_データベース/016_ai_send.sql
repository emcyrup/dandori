-- ============================================================================
--  だんどりシリーズ 共通 / AIの選択と、LINE・メールの送信
--  016_ai_send.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001 → 013 を先に実行しておいてください）
--
--  ここで作るもの
--   ・どのAIを使うかを、法人ごとに選べるようにします
--   ・日報の下書きを保存する場所
--   ・LINE・メールの鍵を、安全にしまう場所
--
--  ★ 鍵のしまい方について
--    tenant_secret には、行の見せ方（RLS）を有効にしたうえで、
--    ポリシーをひとつも作っていません。
--    これにより、画面から使う anon / authenticated では
--    「1行も読めない」状態になります。
--    読めるのは、Supabase の Edge Function が使う service_role だけです。
--    画面からは「設定する」ことはできても、「読み出す」ことはできません。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. AIと送信の設定（法人ごと）
-- ============================================================================
create table if not exists public.tenant_ai (
  tenant_id     uuid primary key references public.tenant(id) on delete cascade,

  -- 使うAI： off / gemini / claude / openai
  ai_provider   text not null default 'off',
  ai_model      text,                              -- 空ならおすすめの既定モデル
  ai_tone       text not null default 'polite',    -- polite（ていねい）/ plain（簡潔）

  -- メールの送り方： off / resend / sendgrid
  mail_provider text not null default 'off',
  mail_from     text,                              -- 差出人のアドレス
  mail_from_name text,                             -- 差出人の表示名

  -- LINE公式アカウントから送るかどうか
  line_enabled  boolean not null default false,

  updated_by    uuid references public.staff(id) on delete set null,
  updated_at    timestamptz not null default now()
);

alter table public.tenant_ai enable row level security;
drop policy if exists p_tenant_ai on public.tenant_ai;
create policy p_tenant_ai on public.tenant_ai for select
  using (tenant_id = app.my_tenant());
-- 書き換えは、下の関数からだけ行います


-- ----------------------------------------------------------------------------
--  鍵のしまい場所（画面からは読めません）
-- ----------------------------------------------------------------------------
create table if not exists public.tenant_secret (
  tenant_id   uuid not null references public.tenant(id) on delete cascade,
  key_name    text not null,      -- line_channel_token / resend_api_key / sendgrid_api_key
  value       text not null,
  updated_by  uuid references public.staff(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (tenant_id, key_name)
);

-- RLS を有効にして、ポリシーは作りません＝画面からは1行も見えません
alter table public.tenant_secret enable row level security;
drop policy if exists p_tenant_secret on public.tenant_secret;

revoke all on public.tenant_secret from anon, authenticated;


-- ----------------------------------------------------------------------------
--  設定を読む（鍵そのものは返しません。「入っているかどうか」だけ返します）
-- ----------------------------------------------------------------------------
create or replace function public.ai_settings_get()
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare me public.staff; s public.tenant_ai;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into s from public.tenant_ai where tenant_id = me.tenant_id;

  return jsonb_build_object(
    'ai_provider',    coalesce(s.ai_provider, 'off'),
    'ai_model',       s.ai_model,
    'ai_tone',        coalesce(s.ai_tone, 'polite'),
    'mail_provider',  coalesce(s.mail_provider, 'off'),
    'mail_from',      s.mail_from,
    'mail_from_name', s.mail_from_name,
    'line_enabled',   coalesce(s.line_enabled, false),
    'has_line_token', exists (select 1 from public.tenant_secret x
                               where x.tenant_id = me.tenant_id
                                 and x.key_name = 'line_channel_token'),
    'has_mail_key',   exists (select 1 from public.tenant_secret x
                               where x.tenant_id = me.tenant_id
                                 and x.key_name in ('resend_api_key','sendgrid_api_key')),
    'can_edit',       me.role = 'owner'
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  設定を書き換える（オーナーだけ）
-- ----------------------------------------------------------------------------
create or replace function public.ai_settings_set(
  p_ai_provider   text default null,
  p_ai_model      text default null,
  p_ai_tone       text default null,
  p_mail_provider text default null,
  p_mail_from     text default null,
  p_mail_from_name text default null,
  p_line_enabled  boolean default null
) returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.role <> 'owner' then
    raise exception 'AIと送信の設定は、オーナーの権限が必要です';
  end if;

  if p_ai_provider is not null
     and p_ai_provider not in ('off','gemini','claude','openai') then
    raise exception 'そのAIは選べません';
  end if;
  if p_mail_provider is not null
     and p_mail_provider not in ('off','resend','sendgrid') then
    raise exception 'そのメールの送り方は選べません';
  end if;
  if p_ai_tone is not null and p_ai_tone not in ('polite','plain') then
    raise exception 'その書き方は選べません';
  end if;

  insert into public.tenant_ai(tenant_id) values (me.tenant_id)
  on conflict (tenant_id) do nothing;

  update public.tenant_ai
     set ai_provider    = coalesce(p_ai_provider, ai_provider),
         ai_model       = case when p_ai_model is null then ai_model
                               else nullif(btrim(p_ai_model), '') end,
         ai_tone        = coalesce(p_ai_tone, ai_tone),
         mail_provider  = coalesce(p_mail_provider, mail_provider),
         mail_from      = case when p_mail_from is null then mail_from
                               else nullif(btrim(p_mail_from), '') end,
         mail_from_name = case when p_mail_from_name is null then mail_from_name
                               else nullif(btrim(p_mail_from_name), '') end,
         line_enabled   = coalesce(p_line_enabled, line_enabled),
         updated_by     = me.id,
         updated_at     = now()
   where tenant_id = me.tenant_id;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, null, me.id, 'ai_settings', 'tenant_ai', me.tenant_id::text,
          jsonb_build_object('ai', p_ai_provider, 'mail', p_mail_provider,
                             'line', p_line_enabled));

  return public.ai_settings_get();
end;
$$;


-- ----------------------------------------------------------------------------
--  鍵をしまう（オーナーだけ。入れたあと、画面からは読み出せません）
-- ----------------------------------------------------------------------------
create or replace function public.secret_set(p_key text, p_value text)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.role <> 'owner' then
    raise exception '鍵の設定は、オーナーの権限が必要です';
  end if;
  if p_key not in ('line_channel_token','resend_api_key','sendgrid_api_key') then
    raise exception 'その鍵は設定できません';
  end if;

  if coalesce(btrim(coalesce(p_value, '')), '') = '' then
    delete from public.tenant_secret
     where tenant_id = me.tenant_id and key_name = p_key;
  else
    insert into public.tenant_secret(tenant_id, key_name, value, updated_by)
    values (me.tenant_id, p_key, btrim(p_value), me.id)
    on conflict (tenant_id, key_name) do update
      set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  end if;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, null, me.id, 'secret_set', 'tenant_secret', p_key,
          jsonb_build_object('key', p_key,
                             'set', coalesce(btrim(coalesce(p_value,'')), '') <> ''));

  return public.ai_settings_get();
end;
$$;


-- ============================================================================
--  2. AIの使用記録（どれだけ使ったか）
-- ============================================================================
create table if not exists public.ai_log (
  id          bigserial primary key,
  tenant_id   uuid references public.tenant(id) on delete cascade,
  store_id    uuid references public.store(id) on delete set null,
  staff_id    uuid references public.staff(id) on delete set null,
  kind        text not null,          -- night_report / cast_report / cast_reception
  provider    text,
  model       text,
  in_chars    integer,
  out_chars   integer,
  ok          boolean not null default true,
  error       text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_ai_log on public.ai_log(tenant_id, created_at desc);

alter table public.ai_log enable row level security;
drop policy if exists p_ai_log on public.ai_log;
create policy p_ai_log on public.ai_log for select
  using (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'));


-- ============================================================================
--  3. 日報（AIの下書きを、そのまま置いておける場所）
-- ============================================================================
create table if not exists public.daily_report (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  business_date date not null,
  body          text not null default '',
  source        text not null default 'ai',     -- ai / manual
  status        text not null default 'draft',  -- draft（未確定）/ confirmed（確定）
  confirmed_by  uuid references public.staff(id) on delete set null,
  confirmed_at  timestamptz,
  updated_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (store_id, business_date)
);

drop trigger if exists trg_touch_daily_report on public.daily_report;
create trigger trg_touch_daily_report before update on public.daily_report
for each row execute function app.touch_updated_at();

alter table public.daily_report enable row level security;
drop policy if exists p_daily_report on public.daily_report;
create policy p_daily_report on public.daily_report for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id));

create or replace function public.report_get(p_store uuid, p_date date)
returns public.daily_report
language plpgsql stable security definer set search_path = public, app
as $$
declare r public.daily_report;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into r from public.daily_report
   where store_id = p_store and business_date = p_date;
  return r;
end;
$$;

create or replace function public.report_save(
  p_store uuid, p_date date, p_body text,
  p_status text default 'draft', p_source text default 'manual')
returns public.daily_report
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; r public.daily_report;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_status not in ('draft','confirmed') then raise exception 'その状態にはできません'; end if;

  select * into st from public.store where id = p_store;

  insert into public.daily_report(
    tenant_id, store_id, business_date, body, source, status,
    confirmed_by, confirmed_at, updated_by)
  values (st.tenant_id, p_store, p_date, coalesce(p_body, ''), p_source, p_status,
          case when p_status = 'confirmed' then me.id end,
          case when p_status = 'confirmed' then now() end,
          me.id)
  on conflict (store_id, business_date) do update
    set body = excluded.body,
        source = excluded.source,
        status = excluded.status,
        confirmed_by = case when excluded.status = 'confirmed'
                            then excluded.confirmed_by else null end,
        confirmed_at = case when excluded.status = 'confirmed'
                            then now() else null end,
        updated_by = excluded.updated_by
  returning * into r;
  return r;
end;
$$;


-- ============================================================================
--  4. AIに渡す材料（数字は、かならずデータベースから取ります）
--
--     AIには「文章にする」ことだけをさせます。
--     数字そのものはここで確定させるので、AIが数字を作ることはありません。
-- ============================================================================
create or replace function public.night_report_input(p_store uuid, p_date date default null)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare st public.store; d date; res jsonb;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  d := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  select jsonb_build_object(
    'kind', 'night_report',
    'store', st.name,
    'date', d,
    'weekday', case extract(dow from d)::integer
      when 0 then '日' when 1 then '月' when 2 then '火' when 3 then '水'
      when 4 then '木' when 5 then '金' else '土' end,
    'sales', (select coalesce(sum(v.total), 0) from public.night_visit v
               where v.store_id = p_store and v.business_date = d and v.status = 'closed'),
    'groups', (select count(*) from public.night_visit v
                where v.store_id = p_store and v.business_date = d and v.status = 'closed'),
    'guests', (select coalesce(sum(v.guests), 0) from public.night_visit v
                where v.store_id = p_store and v.business_date = d and v.status = 'closed'),
    'open_tables', (select count(*) from public.night_visit v
                     where v.store_id = p_store and v.business_date = d and v.status = 'open'),
    'receivable', (select coalesce(sum(r.amount - r.paid_amount), 0)
                     from public.night_receivable r
                    where r.store_id = p_store and r.status <> 'settled'),
    'by_category', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select app.item_label(i.category) as name, sum(i.amount)::integer as amount
          from public.night_visit_item i
          join public.night_visit v on v.id = i.visit_id
         where i.store_id = p_store and v.business_date = d and v.status = 'closed'
         group by 1 order by 2 desc) x),
    'casts', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select c.name,
               count(*) filter (where i.category = 'nomination')::integer as nominations,
               coalesce(sum(i.amount), 0)::integer as sales
          from public.night_visit_item i
          join public.night_visit v on v.id = i.visit_id
          join public.night_cast c on c.id = i.cast_id
         where i.store_id = p_store and v.business_date = d and v.status = 'closed'
         group by c.name order by 3 desc limit 8) x),
    'attendance', (select count(*) from public.night_attendance a
                    where a.store_id = p_store and a.business_date = d
                      and a.clock_in is not null),
    'prev_week_sales', (select coalesce(sum(v.total), 0) from public.night_visit v
                         where v.store_id = p_store and v.business_date = d - 7
                           and v.status = 'closed')
  ) into res;
  return res;
end;
$$;

-- ※ キャストだんどりぶんの材料（cast_report_input など）は、
--   キャストの表ができたあとに入れる必要があるため、
--   108_cast_ai.sql（キャストのまとめファイルの最後）に入れてあります。


-- ============================================================================
--  5. 送信箱を、送る側から扱うための関数
--
--     実際の送信は Edge Function（send-outbox）がおこないます。
--     画面からは「今すぐ送ってください」と頼むだけです。
-- ============================================================================

-- 失敗したものを、もう一度送信待ちに戻します
create or replace function public.outbox_retry(p_id uuid default null)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; n integer;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '送り直しは、店長以上の権限が必要です';
  end if;

  update public.outbox
     set status = 'queued', tries = 0, error = null
   where tenant_id = me.tenant_id
     and status = 'failed'
     and (p_id is null or id = p_id);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- 送信箱の中身（店長以上）
create or replace function public.outbox_list(p_store uuid, p_status text default null)
returns table (
  id uuid, channel text, to_addr text, subject text,
  status text, tries integer, error text,
  created_at timestamptz, sent_at timestamptz, subject_name text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  if app.my_role() not in ('owner','manager') then
    raise exception '送信箱は、店長以上の権限が必要です';
  end if;

  return query
  select o.id, o.channel,
         -- 送り先は、まるごとは出しません（肩越しに見えないように）
         case when length(o.to_addr) > 6
              then left(o.to_addr, 3) || '****' || right(o.to_addr, 3)
              else '****' end,
         o.subject, o.status, o.tries, o.error, o.created_at, o.sent_at,
         p.subject_name
    from public.outbox o
    left join public.payslip p on p.id = o.related_id and o.related_kind = 'payslip'
   where o.store_id = p_store
     and (p_status is null or o.status = p_status)
   order by o.created_at desc
   limit 200;
end;
$$;


-- ============================================================================
--  6. 権限
-- ============================================================================
grant select on public.tenant_ai, public.ai_log to authenticated;
grant select, insert, update, delete on public.daily_report to authenticated;

grant execute on function
  public.ai_settings_get(),
  public.ai_settings_set(text, text, text, text, text, text, boolean),
  public.secret_set(text, text),
  public.report_get(uuid, date),
  public.report_save(uuid, date, text, text, text),
  public.night_report_input(uuid, date),
  public.outbox_retry(uuid),
  public.outbox_list(uuid, text)
to authenticated;


-- ============================================================================
--  7. 送信を自動で回す（任意）
--
--     pg_cron を使うと、5分おきに Edge Function を呼べます。
--     Supabase の SQL Editor で、下の3行のコメントを外して実行してください。
--     〈あなたのプロジェクト〉と〈service_role キー〉は書き換えが必要です。
--     鍵をSQLに書くことになるので、気になる場合は
--     画面の「今すぐ送る」ボタンだけでお使いください。
--
--   create extension if not exists pg_cron;
--   create extension if not exists pg_net;
--   select cron.schedule('send-outbox', '*/5 * * * *', $c$
--     select net.http_post(
--       url := 'https://〈あなたのプロジェクト〉.supabase.co/functions/v1/send-outbox',
--       headers := '{"Content-Type":"application/json",
--                    "Authorization":"Bearer 〈service_role キー〉"}'::jsonb,
--       body := '{}'::jsonb);
--   $c$);
-- ============================================================================
