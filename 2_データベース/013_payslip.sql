-- ============================================================================
--  だんどりシリーズ 共通 / 給与明細・月別履歴・送付
--  013_payslip.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001 → 004 を先に実行しておいてください）
--
--  ここで作るものは、ナイトだけのものではありません。
--  キャスト・フード・サロン・ペット、どの業種でも同じ形で使えるように
--  「payslip（明細）」「outbox（送信箱）」として共通で作っています。
--
--   ・確定した給与を、月ごとの履歴として残す
--   ・給与明細を発行する（発行番号つき・内訳は発行時点で凍結）
--   ・印刷 ／ LINE ／ メール から、ご本人の希望する方法で送る
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 受け取り方の希望（キャストさまごと）
-- ============================================================================
alter table public.night_cast add column if not exists email          text;
alter table public.night_cast add column if not exists line_user_id   text;
-- print … 手渡し・印刷 ／ line … LINE ／ email … メール ／ none … 渡さない
alter table public.night_cast add column if not exists payslip_method text not null default 'print';

comment on column public.night_cast.payslip_method
  is '給与明細の受け取り方。print/line/email/none。ご本人に選んでいただきます。';
comment on column public.night_cast.line_user_id
  is 'LINE公式アカウントの友だち登録でわかるID。お店のLINE公式アカウントから送るために使います。';


-- ============================================================================
--  2. 明細の書式（店舗ごと）
--     実際にお使いの用紙に合わせて、ここを書き換えます。
-- ============================================================================
alter table public.store add column if not exists payslip_title    text
  not null default '給与明細書';
alter table public.store add column if not exists payslip_issuer   text;   -- 発行者名（屋号・法人名）
alter table public.store add column if not exists payslip_note     text;   -- 明細の下に入れる定型文
alter table public.store add column if not exists payslip_layout   jsonb
  not null default '{}'::jsonb;  -- 並び順・表示する項目などの細かい指定


-- ============================================================================
--  3. 明細（全業種で共通）
-- ============================================================================
create table if not exists public.payslip (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,

  -- 誰あてか。業種でテーブルが違うので、種類とIDで持ちます。
  --   night_cast … ナイトのキャストさま
  --   cast_member … キャストだんどりのキャストさま
  --   staff       … 従業員
  subject_kind  text not null default 'night_cast',
  subject_id    uuid not null,
  subject_name  text not null,                 -- 発行時点のお名前（あとで改名しても明細は動きません）

  period_from   date not null,
  period_to     date not null,
  period_ym     text not null,                 -- '2026-09'。月別にまとめるための列
  issue_no      integer not null,              -- 店舗ごとの通し番号
  issued_at     timestamptz not null default now(),
  issued_by     uuid references public.staff(id) on delete set null,

  gross         integer not null default 0,    -- 支給の合計
  deduction     integer not null default 0,    -- 控除の合計
  advance       integer not null default 0,    -- 日払い済み
  net           integer not null default 0,    -- 差引支給額

  -- issued … 発行済み ／ sent … 送った ／ void … 取り消し
  status        text not null default 'issued',
  method        text,                          -- 実際に送った方法 print/line/email
  sent_at       timestamptz,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (store_id, issue_no)
);
create index if not exists idx_payslip_subject
  on public.payslip(subject_kind, subject_id, period_ym desc);
create index if not exists idx_payslip_store
  on public.payslip(store_id, period_ym desc);

-- 明細の中身。発行した時点の数字を写し取るので、あとから料金や時給を直しても動きません。
create table if not exists public.payslip_line (
  id          uuid primary key default gen_random_uuid(),
  payslip_id  uuid not null references public.payslip(id) on delete cascade,
  -- earning … 支給 ／ deduction … 控除 ／ info … 参考（出勤日数など、金額に入れないもの）
  section     text not null default 'earning',
  label       text not null,
  qty         numeric(12,2),                   -- 時間数・本数など
  unit        text,                            -- '時間' '本' '回'
  amount      integer not null default 0,
  sort_no     integer not null default 100,
  created_at  timestamptz not null default now()
);
create index if not exists idx_payslip_line on public.payslip_line(payslip_id, sort_no);

drop trigger if exists trg_touch_payslip on public.payslip;
create trigger trg_touch_payslip before update on public.payslip
for each row execute function app.touch_updated_at();


-- ============================================================================
--  4. 送信箱（LINE・メールの送信待ち）
--
--     この表に積むところまでが、このツールの仕事です。
--     実際の送信は、Supabase の Edge Function が順に拾って送ります。
--     （LINE公式アカウントのトークンや、メール送信の鍵は、
--       データベースには置きません。Edge Function 側の秘密として持ちます）
-- ============================================================================
create table if not exists public.outbox (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant(id) on delete cascade,
  store_id     uuid not null references public.store(id) on delete cascade,
  channel      text not null,                  -- line / email
  to_addr      text not null,                  -- LINEのID、またはメールアドレス
  subject      text,
  body         text not null,
  attach_path  text,                           -- Storage に置いたPDFの場所
  related_kind text,                           -- 'payslip' など
  related_id   uuid,
  -- queued … 送信待ち ／ sent … 送信済み ／ failed … 失敗 ／ canceled … 取り消し
  status       text not null default 'queued',
  tries        integer not null default 0,
  error        text,
  sent_at      timestamptz,
  created_by   uuid references public.staff(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_outbox_queue on public.outbox(status, created_at);
create index if not exists idx_outbox_related on public.outbox(related_kind, related_id);

drop trigger if exists trg_touch_outbox on public.outbox;
create trigger trg_touch_outbox before update on public.outbox
for each row execute function app.touch_updated_at();


-- ============================================================================
--  5. 明細を発行する
--
--     確定した給与（night_payroll）から作ります。
--     まだ確定していない期間は、先に「給与を確定する」を押してください。
--     同じ期間を2度発行しようとした場合は、前の明細を取り消してから作り直します。
-- ============================================================================
create or replace function public.night_payslip_issue(
  p_store uuid, p_from date, p_to date, p_cast uuid default null
) returns integer
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; st public.store; r record;
  v_id uuid; v_no integer; n integer := 0; v_ym text;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '給与明細の発行は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = p_store;
  v_ym := to_char(p_to, 'YYYY-MM');

  for r in
    select p.*, c.name as cast_name, c.payslip_method
      from public.night_payroll p
      join public.night_cast c on c.id = p.cast_id
     where p.store_id = p_store
       and p.period_from = p_from and p.period_to = p_to
       and (p_cast is null or p.cast_id = p_cast)
     order by c.name
  loop
    -- 同じ人・同じ期間の、生きている明細は取り消してから作り直します
    update public.payslip
       set status = 'void',
           note = coalesce(note || ' / ', '') || '作り直しのため取消'
     where store_id = p_store
       and subject_kind = 'night_cast' and subject_id = r.cast_id
       and period_from = p_from and period_to = p_to
       and status <> 'void';

    select coalesce(max(issue_no), 0) + 1 into v_no
      from public.payslip where store_id = p_store;

    insert into public.payslip(
      tenant_id, store_id, subject_kind, subject_id, subject_name,
      period_from, period_to, period_ym, issue_no, issued_by,
      gross, deduction, advance, net, status)
    values (
      st.tenant_id, p_store, 'night_cast', r.cast_id, r.cast_name,
      p_from, p_to, v_ym, v_no, me.id,
      r.wage_amount + r.back_amount + r.allowance,
      r.deduction, r.advance, r.net_amount, 'issued')
    returning id into v_id;

    insert into public.payslip_line(payslip_id, section, label, qty, unit, amount, sort_no)
    values
      (v_id, 'info',      '出勤時間',   round(r.work_minutes::numeric / 60, 2), '時間', 0, 10),
      (v_id, 'info',      '本指名',     r.nominations, '本', 0, 20),
      (v_id, 'info',      '同伴',       r.douhans,     '回', 0, 30),
      (v_id, 'earning',   '時給ぶん',   round(r.work_minutes::numeric / 60, 2), '時間',
                                        r.wage_amount, 110),
      (v_id, 'earning',   'バック',     null, null, r.back_amount, 120),
      (v_id, 'earning',   '手当',       null, null, r.allowance,   130),
      (v_id, 'deduction', '控除',       null, null, r.deduction,   210),
      (v_id, 'deduction', '日払い済み', null, null, r.advance,     220);

    -- 金額が0の行は、明細に出しません（用紙が見にくくなるため）
    delete from public.payslip_line
     where payslip_id = v_id and section in ('earning','deduction') and amount = 0;
    delete from public.payslip_line
     where payslip_id = v_id and section = 'info' and coalesce(qty, 0) = 0;

    n := n + 1;
  end loop;

  if n = 0 then
    raise exception 'この期間の確定した給与がありません。先に給与を確定してください';
  end if;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (st.tenant_id, p_store, me.id, 'payslip_issue', 'payslip', null,
          jsonb_build_object('from', p_from, 'to', p_to, 'count', n));

  return n;
end;
$$;


-- ============================================================================
--  6. 明細を読む（印刷用）
-- ============================================================================
create or replace function public.payslip_get(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare p public.payslip; st public.store; t public.tenant;
begin
  select * into p from public.payslip where id = p_id;
  if not found then raise exception '明細が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この明細を見る権限がありません'; end if;

  select * into st from public.store  where id = p.store_id;
  select * into t  from public.tenant where id = p.tenant_id;

  return jsonb_build_object(
    'id', p.id,
    'title', st.payslip_title,
    'issuer', coalesce(st.payslip_issuer, t.name),
    'store', st.name,
    'store_tel', st.tel,
    'store_address', st.address,
    'foot_note', st.payslip_note,
    'layout', st.payslip_layout,
    'issue_no', p.issue_no,
    'issued_at', p.issued_at,
    'subject_name', p.subject_name,
    'subject_kind', p.subject_kind,
    'subject_id', p.subject_id,
    'period_from', p.period_from,
    'period_to', p.period_to,
    'period_ym', p.period_ym,
    'gross', p.gross,
    'deduction', p.deduction,
    'advance', p.advance,
    'net', p.net,
    'status', p.status,
    'method', p.method,
    'sent_at', p.sent_at,
    'note', p.note,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'section', l.section, 'label', l.label,
        'qty', l.qty, 'unit', l.unit, 'amount', l.amount) order by l.sort_no)
      from public.payslip_line l where l.payslip_id = p.id), '[]'::jsonb)
  );
end;
$$;


-- ============================================================================
--  7. 明細の一覧（期間で）
-- ============================================================================
create or replace function public.payslip_list(
  p_store uuid, p_ym text default null, p_kind text default null
)
returns table (
  id uuid, issue_no integer, period_ym text,
  period_from date, period_to date,
  subject_kind text, subject_id uuid, subject_name text,
  gross integer, deduction integer, advance integer, net integer,
  status text, method text, sent_at timestamptz,
  want_method text, contact text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select p.id, p.issue_no, p.period_ym, p.period_from, p.period_to,
         p.subject_kind, p.subject_id, p.subject_name,
         p.gross, p.deduction, p.advance, p.net,
         p.status, p.method, p.sent_at,
         c.payslip_method,
         case c.payslip_method
           when 'line'  then nullif(c.line_user_id, '')
           when 'email' then nullif(c.email, '')
           else null end
    from public.payslip p
    left join public.night_cast c
           on p.subject_kind = 'night_cast' and c.id = p.subject_id
   where p.store_id = p_store
     and (p_ym is null or p.period_ym = p_ym)
     and (p_kind is null or p.subject_kind = p_kind)
   order by p.period_ym desc, p.issue_no;
end;
$$;


-- ============================================================================
--  8. 月別の履歴
--
--     8-1. 店舗の月別（人数と支給総額の推移）
--     8-2. ご本人の月別（12か月ぶんの推移）
--     どちらも、確定した給与（night_payroll）をもとにしています。
-- ============================================================================
create or replace function public.night_payroll_monthly(
  p_store uuid, p_months integer default 12
)
returns table (
  period_ym   text,
  people      integer,
  work_hours  numeric,
  wage_amount integer,
  back_amount integer,
  allowance   integer,
  deduction   integer,
  advance     integer,
  net_amount  integer,
  payslips    integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare m integer;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  m := greatest(least(coalesce(p_months, 12), 36), 1);

  return query
  with months as (
    select to_char(d, 'YYYY-MM') as ym
      from generate_series(
        date_trunc('month', current_date) - make_interval(months => m - 1),
        date_trunc('month', current_date),
        interval '1 month') d
  ),
  agg as (
    select to_char(p.period_to, 'YYYY-MM') as ym,
           count(distinct p.cast_id)::integer as people,
           round(sum(p.work_minutes)::numeric / 60, 1) as work_hours,
           sum(p.wage_amount)::integer as wage_amount,
           sum(p.back_amount)::integer as back_amount,
           sum(p.allowance)::integer   as allowance,
           sum(p.deduction)::integer   as deduction,
           sum(p.advance)::integer     as advance,
           sum(p.net_amount)::integer  as net_amount
      from public.night_payroll p
     where p.store_id = p_store
     group by 1
  ),
  slip as (
    select s.period_ym as ym, count(*)::integer as payslips
      from public.payslip s
     where s.store_id = p_store and s.status <> 'void'
     group by 1
  )
  select mo.ym,
         coalesce(a.people, 0), coalesce(a.work_hours, 0),
         coalesce(a.wage_amount, 0), coalesce(a.back_amount, 0),
         coalesce(a.allowance, 0), coalesce(a.deduction, 0),
         coalesce(a.advance, 0), coalesce(a.net_amount, 0),
         coalesce(s.payslips, 0)
    from months mo
    left join agg  a on a.ym = mo.ym
    left join slip s on s.ym = mo.ym
   order by mo.ym;
end;
$$;

create or replace function public.night_payroll_cast_history(
  p_cast uuid, p_months integer default 12
)
returns table (
  period_ym    text,
  period_from  date,
  period_to    date,
  work_hours   numeric,
  nominations  integer,
  wage_amount  integer,
  back_amount  integer,
  allowance    integer,
  deduction    integer,
  advance      integer,
  net_amount   integer,
  payslip_id   uuid,
  payslip_no   integer,
  sent_method  text,
  sent_at      timestamptz
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare c public.night_cast; m integer;
begin
  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を見る権限がありません'; end if;
  m := greatest(least(coalesce(p_months, 12), 60), 1);

  return query
  select to_char(p.period_to, 'YYYY-MM'),
         p.period_from, p.period_to,
         round(p.work_minutes::numeric / 60, 1),
         p.nominations,
         p.wage_amount, p.back_amount, p.allowance,
         p.deduction, p.advance, p.net_amount,
         s.id, s.issue_no, s.method, s.sent_at
    from public.night_payroll p
    left join public.payslip s
           on s.subject_kind = 'night_cast' and s.subject_id = p.cast_id
          and s.period_from = p.period_from and s.period_to = p.period_to
          and s.status <> 'void'
   where p.cast_id = p_cast
     and p.period_to >= (date_trunc('month', current_date)
                         - make_interval(months => m - 1))::date
   order by p.period_to desc;
end;
$$;


-- ============================================================================
--  9. 送る
--
--     ご本人の希望した方法で送ります（希望の指定がなければ、印刷あつかい）。
--     ・print … 印刷して手渡し。画面から印刷したあとに「渡した」記録を残します
--     ・line  … お店のLINE公式アカウントから送ります
--     ・email … メールで送ります
--
--     line / email は、この関数では「送信箱」に積むところまでです。
--     実際の送信は Edge Function がおこない、成功したら状態を sent に変えます。
-- ============================================================================
create or replace function public.payslip_send(
  p_id uuid, p_method text default null, p_attach_path text default null
) returns public.payslip
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; p public.payslip; st public.store;
  v_method text; v_to text; v_body text; v_subject text;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '明細を送るのは、店長以上の権限が必要です';
  end if;

  select * into p from public.payslip where id = p_id;
  if not found then raise exception '明細が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p.status = 'void' then raise exception '取り消した明細は送れません'; end if;

  select * into st from public.store where id = p.store_id;

  -- 方法：指定がなければ、ご本人の希望を使います
  v_method := coalesce(
    nullif(p_method, ''),
    (select c.payslip_method from public.night_cast c
      where p.subject_kind = 'night_cast' and c.id = p.subject_id),
    'print');

  if v_method = 'none' then
    raise exception 'この方には「渡さない」の設定になっています';
  end if;
  if v_method not in ('print','line','email') then
    raise exception 'その送り方は選べません';
  end if;

  if v_method in ('line','email') then
    select case v_method
             when 'line'  then nullif(c.line_user_id, '')
             when 'email' then nullif(c.email, '') end
      into v_to
      from public.night_cast c
     where p.subject_kind = 'night_cast' and c.id = p.subject_id;

    if v_to is null then
      raise exception '%の送り先が登録されていません。名簿で登録してください',
        case v_method when 'line' then 'LINE' else 'メール' end;
    end if;

    v_subject := st.payslip_title || '（' || p.period_ym || '）';
    v_body :=
      p.subject_name || ' さま' || E'\n\n' ||
      p.period_ym || 'ぶんの' || st.payslip_title || 'です。' || E'\n' ||
      '対象期間： ' || to_char(p.period_from, 'YYYY/MM/DD') || ' 〜 ' ||
                      to_char(p.period_to,   'YYYY/MM/DD') || E'\n' ||
      '差引支給額： ' || to_char(p.net, 'FM9,999,999') || ' 円' || E'\n\n' ||
      coalesce(st.payslip_note || E'\n\n', '') ||
      coalesce(st.name, '') ||
      case when st.tel is not null then E'\n' || st.tel else '' end;

    insert into public.outbox(
      tenant_id, store_id, channel, to_addr, subject, body,
      attach_path, related_kind, related_id, created_by)
    values (p.tenant_id, p.store_id, v_method, v_to, v_subject, v_body,
            p_attach_path, 'payslip', p.id, me.id);
  end if;

  update public.payslip
     set method = v_method,
         status = case when v_method = 'print' then 'sent' else status end,
         sent_at = case when v_method = 'print' then now() else sent_at end
   where id = p_id
   returning * into p;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (p.tenant_id, p.store_id, me.id, 'payslip_send', 'payslip', p.id::text,
          jsonb_build_object('method', v_method, 'to_name', p.subject_name));

  return p;
end;
$$;

-- まとめて送る（その月の、まだ送っていない明細を、それぞれの希望の方法で）
create or replace function public.payslip_send_all(p_store uuid, p_ym text)
returns table (sent integer, skipped integer, detail jsonb)
language plpgsql security definer set search_path = public, app
as $$
#variable_conflict use_column
declare r record; n integer := 0; k integer := 0; d jsonb := '[]'::jsonb;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  for r in select p.id, p.subject_name from public.payslip p
            where p.store_id = p_store and p.period_ym = p_ym
              and p.status = 'issued'
            order by p.issue_no
  loop
    begin
      perform public.payslip_send(r.id, null, null);
      n := n + 1;
    exception when others then
      k := k + 1;
      d := d || jsonb_build_object('name', r.subject_name, 'reason', SQLERRM);
    end;
  end loop;

  return query select n, k, d;
end;
$$;

-- 取り消し
create or replace function public.payslip_void(p_id uuid, p_reason text default null)
returns public.payslip
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; p public.payslip;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '明細の取り消しは、店長以上の権限が必要です';
  end if;

  select * into p from public.payslip where id = p_id;
  if not found then raise exception '明細が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.outbox set status = 'canceled'
   where related_kind = 'payslip' and related_id = p_id and status = 'queued';

  update public.payslip
     set status = 'void',
         note = case when p_reason is null or btrim(p_reason) = '' then note
                     else coalesce(note || ' / ', '') || '取消: ' || p_reason end
   where id = p_id returning * into p;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (p.tenant_id, p.store_id, me.id, 'payslip_void', 'payslip', p.id::text,
          jsonb_build_object('reason', p_reason));
  return p;
end;
$$;

-- 受け取り方の希望を登録する
create or replace function public.night_cast_contact_set(
  p_cast uuid, p_method text, p_email text default null, p_line text default null)
returns public.night_cast
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '受け取り方の登録は、店長以上の権限が必要です';
  end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  if p_method not in ('print','line','email','none') then
    raise exception 'その受け取り方は選べません';
  end if;
  if p_method = 'email' and coalesce(btrim(p_email), '') = ''
     and coalesce(btrim(c.email), '') = '' then
    raise exception 'メールで受け取るには、メールアドレスが必要です';
  end if;
  if p_method = 'line' and coalesce(btrim(p_line), '') = ''
     and coalesce(btrim(c.line_user_id), '') = '' then
    raise exception 'LINEで受け取るには、LINEの友だち登録が必要です';
  end if;

  update public.night_cast
     set payslip_method = p_method,
         email        = coalesce(nullif(btrim(p_email), ''), email),
         line_user_id = coalesce(nullif(btrim(p_line),  ''), line_user_id)
   where id = p_cast returning * into c;
  return c;
end;
$$;


-- ============================================================================
--  10. 送信箱の様子（画面用）
-- ============================================================================
create or replace function public.outbox_status(p_store uuid)
returns table (channel text, queued integer, sent integer, failed integer, last_error text)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  return query
  select o.channel,
         count(*) filter (where o.status = 'queued')::integer,
         count(*) filter (where o.status = 'sent')::integer,
         count(*) filter (where o.status = 'failed')::integer,
         (array_agg(o.error order by o.updated_at desc)
            filter (where o.status = 'failed'))[1]
    from public.outbox o
   where o.store_id = p_store
   group by o.channel;
end;
$$;


-- ============================================================================
--  11. 行の見せ方（RLS）と権限
--
--     明細は、店長以上だけが見られます。
--     （ほかのキャストさまの金額が見えないようにするためです）
-- ============================================================================
alter table public.payslip      enable row level security;
alter table public.payslip_line enable row level security;
alter table public.outbox       enable row level security;

drop policy if exists p_payslip on public.payslip;
create policy p_payslip on public.payslip for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id)
         and app.my_role() in ('owner','manager'))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id)
         and app.my_role() in ('owner','manager'));

drop policy if exists p_payslip_line on public.payslip_line;
create policy p_payslip_line on public.payslip_line for all
  using (exists (select 1 from public.payslip p
                 where p.id = payslip_id
                   and p.tenant_id = app.my_tenant()
                   and app.can_store(p.store_id)
                   and app.my_role() in ('owner','manager')))
  with check (exists (select 1 from public.payslip p
                 where p.id = payslip_id
                   and p.tenant_id = app.my_tenant()
                   and app.can_store(p.store_id)
                   and app.my_role() in ('owner','manager')));

drop policy if exists p_outbox on public.outbox;
create policy p_outbox on public.outbox for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id)
         and app.my_role() in ('owner','manager'))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id)
         and app.my_role() in ('owner','manager'));

grant select, insert, update, delete on
  public.payslip, public.payslip_line, public.outbox
to authenticated;

grant execute on function
  public.night_payslip_issue(uuid, date, date, uuid),
  public.payslip_get(uuid),
  public.payslip_list(uuid, text, text),
  public.payslip_send(uuid, text, text),
  public.payslip_send_all(uuid, text),
  public.payslip_void(uuid, text),
  public.night_payroll_monthly(uuid, integer),
  public.night_payroll_cast_history(uuid, integer),
  public.night_cast_contact_set(uuid, text, text, text),
  public.outbox_status(uuid)
to authenticated;


-- ============================================================================
--  確認用
--   select public.night_payslip_issue('店舗ID', '2026-09-01', '2026-09-30');
--   select * from public.payslip_list('店舗ID', '2026-09');
--   select * from public.night_payroll_monthly('店舗ID', 12);
-- ============================================================================
