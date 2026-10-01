-- ============================================================================
--  だんどりシリーズ 共通 / 過去データの取り込み
--  014_import.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001 → 004 → 005 → 009 → 013 を先に実行しておいてください）
--
--  ここで作るものも、ナイトだけのものではありません。
--  どの業種でも同じ形で使えるように、共通の「取り込み」として作っています。
--
--   ・CSV を読み込んで、確認してから反映する
--   ・PDF や写真（手書きの名簿・給与台帳など）を預かって、
--     中身を1行ずつ起こしてから反映する
--
--  いきなり本番のデータを書き換えることはしません。
--  かならず「取り込み箱」に入れて、画面で確認してから反映します。
--  まちがえたら、その取り込みごと取り消せます。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 取り込みの単位（1回のアップロード＝1件）
-- ============================================================================
create table if not exists public.import_batch (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant(id) on delete cascade,
  store_id     uuid not null references public.store(id) on delete cascade,

  -- 何を取り込むか
  --   cast       … 在籍名簿
  --   customer   … 顧客台帳
  --   attendance … 過去の出勤記録
  --   payroll    … 過去の給与（月別の履歴になります）
  kind         text not null,
  -- どこから来たか  csv / pdf / image / manual
  source       text not null default 'csv',

  file_name    text,
  row_count    integer not null default 0,
  ok_count     integer not null default 0,
  ng_count     integer not null default 0,
  -- uploaded … 預かった ／ reviewing … 確認中 ／ applied … 反映済み
  -- canceled … 取り消し ／ reverted … 反映を取り消した
  status       text not null default 'uploaded',
  note         text,
  created_by   uuid references public.staff(id) on delete set null,
  applied_by   uuid references public.staff(id) on delete set null,
  applied_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_import_batch_store
  on public.import_batch(store_id, created_at desc);

-- 預かったファイル（PDFは複数ページ、写真は複数枚になることがあります）
create table if not exists public.import_file (
  id         uuid primary key default gen_random_uuid(),
  batch_id   uuid not null references public.import_batch(id) on delete cascade,
  path       text not null,                  -- Storage の imports バケット内の場所
  file_name  text,
  mime       text,
  page_no    integer not null default 1,
  bytes      integer,
  created_at timestamptz not null default now()
);
create index if not exists idx_import_file on public.import_file(batch_id, page_no);

-- 1行ぶんのデータ
create table if not exists public.import_row (
  id         uuid primary key default gen_random_uuid(),
  batch_id   uuid not null references public.import_batch(id) on delete cascade,
  line_no    integer not null,
  raw        jsonb not null default '{}'::jsonb,   -- 読み取ったままの内容
  mapped     jsonb not null default '{}'::jsonb,   -- 画面で整えたあとの内容
  -- new … 未確認 ／ ok … 反映してよい ／ ng … 直しが要る
  -- skip … 飛ばす ／ applied … 反映済み
  status     text not null default 'new',
  error      text,
  target_id  uuid,                                  -- 反映してできた行のID
  created_at timestamptz not null default now(),
  unique (batch_id, line_no)
);
create index if not exists idx_import_row on public.import_row(batch_id, line_no);

do $$
declare t text;
begin
  foreach t in array array['import_batch'] loop
    execute format('drop trigger if exists trg_touch_%1$s on public.%1$s', t);
    execute format(
      'create trigger trg_touch_%1$s before update on public.%1$s
       for each row execute function app.touch_updated_at()', t);
  end loop;
end $$;


-- ============================================================================
--  2. 取り込みを始める
-- ============================================================================
create or replace function public.import_create(
  p_store uuid, p_kind text, p_source text default 'csv',
  p_file_name text default null, p_note text default null
) returns public.import_batch
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; b public.import_batch;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '過去データの取り込みは、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;

  if p_kind not in ('cast','customer','attendance','payroll') then
    raise exception 'その種類は取り込めません（cast / customer / attendance / payroll）';
  end if;
  if p_source not in ('csv','pdf','image','manual') then
    raise exception 'その取り込み元は選べません';
  end if;

  select * into st from public.store where id = p_store;

  insert into public.import_batch(
    tenant_id, store_id, kind, source, file_name, note, created_by)
  values (st.tenant_id, p_store, p_kind, p_source, p_file_name, p_note, me.id)
  returning * into b;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (st.tenant_id, p_store, me.id, 'import_create', 'import_batch', b.id::text,
          jsonb_build_object('kind', p_kind, 'source', p_source, 'file', p_file_name));

  return b;
end;
$$;

-- 預かったファイルを登録する（先に Storage の imports バケットへ上げてから）
create or replace function public.import_file_add(
  p_batch uuid, p_path text, p_file_name text default null,
  p_mime text default null, p_page integer default 1, p_bytes integer default null
) returns public.import_file
language plpgsql security definer set search_path = public, app
as $$
declare b public.import_batch; f public.import_file;
begin
  select * into b from public.import_batch where id = p_batch;
  if not found then raise exception '取り込みが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  insert into public.import_file(batch_id, path, file_name, mime, page_no, bytes)
  values (p_batch, p_path, p_file_name, p_mime, coalesce(p_page,1), p_bytes)
  returning * into f;
  return f;
end;
$$;


-- ============================================================================
--  3. 行を入れる
--     CSVは画面で読み取って、この関数にまとめて渡します。
--     PDF・写真は、読み取った内容を1行ずつ、同じ形で渡します。
-- ============================================================================
create or replace function public.import_rows_add(p_batch uuid, p_rows jsonb)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare b public.import_batch; v_next integer; n integer := 0;
begin
  select * into b from public.import_batch where id = p_batch;
  if not found then raise exception '取り込みが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if b.status in ('applied','canceled') then
    raise exception 'この取り込みには、もう足せません';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception '行の形が違います（配列で渡してください）';
  end if;

  select coalesce(max(line_no), 0) into v_next from public.import_row where batch_id = p_batch;

  insert into public.import_row(batch_id, line_no, raw, mapped)
  select p_batch, v_next + row_number() over (), e, e
    from jsonb_array_elements(p_rows) e;
  get diagnostics n = row_count;

  update public.import_batch
     set row_count = (select count(*) from public.import_row where batch_id = p_batch),
         status = case when status = 'uploaded' then 'reviewing' else status end
   where id = p_batch;

  return n;
end;
$$;

-- 画面で1行を直す
create or replace function public.import_row_set(
  p_row uuid, p_mapped jsonb default null, p_status text default null)
returns public.import_row
language plpgsql security definer set search_path = public, app
as $$
declare r public.import_row; b public.import_batch;
begin
  select * into r from public.import_row where id = p_row;
  if not found then raise exception 'その行はありません'; end if;
  select * into b from public.import_batch where id = r.batch_id;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if r.status = 'applied' then raise exception '反映済みの行は直せません'; end if;

  if p_status is not null and p_status not in ('new','ok','ng','skip') then
    raise exception 'その状態にはできません';
  end if;

  update public.import_row
     set mapped = coalesce(p_mapped, mapped),
         status = coalesce(p_status, status),
         error  = case when p_status = 'ok' then null else error end
   where id = p_row returning * into r;
  return r;
end;
$$;


-- ============================================================================
--  4. 中身をたしかめる（反映する前のチェック）
--     足りない項目・おかしい日付などを、行ごとに指摘します。
-- ============================================================================
create or replace function app.import_check_row(p_kind text, p_store uuid, m jsonb)
returns text
language plpgsql stable security definer set search_path = public, app
as $$
declare st public.store;
begin
  select * into st from public.store where id = p_store;

  if p_kind = 'cast' then
    if coalesce(btrim(m->>'name'), '') = '' then return 'お名前が空です'; end if;
    if (m ? 'hourly_wage') and (m->>'hourly_wage') !~ '^-?[0-9]+$' then
      return '時給が数字ではありません'; end if;
    if (m ? 'birthday') and coalesce(btrim(m->>'birthday'),'') <> ''
       and app.age_on((m->>'birthday')::date, coalesce(nullif(m->>'joined_on','')::date, current_date)) < 18 then
      return '入店日の時点で18歳未満です。登録できません';
    end if;

  elsif p_kind = 'customer' then
    if coalesce(btrim(m->>'name'), '') = '' then return 'お名前が空です'; end if;

  elsif p_kind = 'attendance' then
    if coalesce(btrim(m->>'cast_name'), '') = '' then return 'キャストのお名前が空です'; end if;
    if coalesce(btrim(m->>'business_date'), '') = '' then return '営業日が空です'; end if;
    if not exists (select 1 from public.night_cast c
                    where c.store_id = p_store and c.name = btrim(m->>'cast_name')) then
      return '「' || (m->>'cast_name') || '」が名簿にいません。先に名簿を取り込んでください';
    end if;

  elsif p_kind = 'payroll' then
    if coalesce(btrim(m->>'cast_name'), '') = '' then return 'キャストのお名前が空です'; end if;
    if coalesce(btrim(m->>'period_from'), '') = '' or coalesce(btrim(m->>'period_to'), '') = '' then
      return '対象期間（開始・終了）が空です'; end if;
    if not exists (select 1 from public.night_cast c
                    where c.store_id = p_store and c.name = btrim(m->>'cast_name')) then
      return '「' || (m->>'cast_name') || '」が名簿にいません。先に名簿を取り込んでください';
    end if;
  end if;

  return null;
exception when others then
  return '読み取れない値があります（' || SQLERRM || '）';
end;
$$;

create or replace function public.import_check(p_batch uuid)
returns table (ok integer, ng integer)
language plpgsql security definer set search_path = public, app
as $$
#variable_conflict use_column
declare b public.import_batch; r record; e text; a integer := 0; g integer := 0;
begin
  select * into b from public.import_batch where id = p_batch;
  if not found then raise exception '取り込みが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  for r in select * from public.import_row
            where batch_id = p_batch and status <> 'applied' and status <> 'skip'
  loop
    e := app.import_check_row(b.kind, b.store_id, r.mapped);
    if e is null then
      update public.import_row set status = 'ok', error = null where id = r.id;
      a := a + 1;
    else
      update public.import_row set status = 'ng', error = e where id = r.id;
      g := g + 1;
    end if;
  end loop;

  update public.import_batch set ok_count = a, ng_count = g, status = 'reviewing'
   where id = p_batch;

  return query select a, g;
end;
$$;


-- ============================================================================
--  5. 反映する
--     「ok」になっている行だけを、本番のデータに書き込みます。
--     同じお名前・同じ期間のものは、上書きします（二重に増えません）。
-- ============================================================================
create or replace function app.import_apply_row(
  p_kind text, p_tenant uuid, p_store uuid, m jsonb)
returns uuid
language plpgsql security definer set search_path = public, app
as $$
declare v_id uuid; v_cast uuid; v_from date; v_to date;
begin
  if p_kind = 'cast' then
    select id into v_cast from public.night_cast
     where store_id = p_store and name = btrim(m->>'name') limit 1;

    if v_cast is null then
      insert into public.night_cast(
        tenant_id, store_id, name, real_name, hourly_wage, joined_on, left_on, is_active)
      values (p_tenant, p_store, btrim(m->>'name'),
              nullif(btrim(coalesce(m->>'real_name','')), ''),
              coalesce(nullif(m->>'hourly_wage','')::integer, 0),
              nullif(m->>'joined_on','')::date,
              nullif(m->>'left_on','')::date,
              coalesce(nullif(m->>'left_on','') is null, true))
      returning id into v_cast;
    else
      update public.night_cast
         set real_name   = coalesce(nullif(btrim(coalesce(m->>'real_name','')),''), real_name),
             hourly_wage = coalesce(nullif(m->>'hourly_wage','')::integer, hourly_wage),
             joined_on   = coalesce(nullif(m->>'joined_on','')::date, joined_on),
             left_on     = coalesce(nullif(m->>'left_on','')::date, left_on)
       where id = v_cast;
    end if;

    -- 名簿の項目（005_roster.sql の列。無い場合は飛ばします）
    begin
      update public.night_cast
         set birthday = coalesce(nullif(m->>'birthday','')::date, birthday),
             tel      = coalesce(nullif(btrim(coalesce(m->>'tel','')),''), tel),
             address  = coalesce(nullif(btrim(coalesce(m->>'address','')),''), address)
       where id = v_cast;
    exception when undefined_column then null;
    end;

    begin
      update public.night_cast
         set email        = coalesce(nullif(btrim(coalesce(m->>'email','')),''), email),
             line_user_id = coalesce(nullif(btrim(coalesce(m->>'line_user_id','')),''), line_user_id)
       where id = v_cast;
    exception when undefined_column then null;
    end;

    return v_cast;

  elsif p_kind = 'customer' then
    select id into v_id from public.night_customer
     where store_id = p_store and name = btrim(m->>'name') limit 1;

    if v_id is null then
      insert into public.night_customer(tenant_id, store_id, name, tel, note)
      values (p_tenant, p_store, btrim(m->>'name'),
              nullif(btrim(coalesce(m->>'tel','')),''),
              nullif(btrim(coalesce(m->>'note','')),''))
      returning id into v_id;
    else
      update public.night_customer
         set tel  = coalesce(nullif(btrim(coalesce(m->>'tel','')),''), tel),
             note = coalesce(nullif(btrim(coalesce(m->>'note','')),''), note)
       where id = v_id;
    end if;
    return v_id;

  elsif p_kind = 'attendance' then
    select id into v_cast from public.night_cast
     where store_id = p_store and name = btrim(m->>'cast_name') limit 1;

    insert into public.night_attendance(
      tenant_id, store_id, cast_id, business_date, clock_in, clock_out, late_minutes, note)
    values (p_tenant, p_store, v_cast, (m->>'business_date')::date,
            nullif(m->>'clock_in','')::timestamptz,
            nullif(m->>'clock_out','')::timestamptz,
            coalesce(nullif(m->>'late_minutes','')::integer, 0),
            nullif(btrim(coalesce(m->>'note','')),'') )
    on conflict (cast_id, business_date) do update
      set clock_in     = coalesce(excluded.clock_in, public.night_attendance.clock_in),
          clock_out    = coalesce(excluded.clock_out, public.night_attendance.clock_out),
          late_minutes = excluded.late_minutes,
          note         = coalesce(excluded.note, public.night_attendance.note)
    returning id into v_id;
    return v_id;

  elsif p_kind = 'payroll' then
    select id into v_cast from public.night_cast
     where store_id = p_store and name = btrim(m->>'cast_name') limit 1;
    v_from := (m->>'period_from')::date;
    v_to   := (m->>'period_to')::date;

    insert into public.night_payroll(
      tenant_id, store_id, cast_id, period_from, period_to,
      work_minutes, hourly_applied, wage_amount, back_amount,
      allowance, deduction, advance, net_amount, nominations, douhans,
      status, note)
    values (
      p_tenant, p_store, v_cast, v_from, v_to,
      coalesce(nullif(m->>'work_minutes','')::integer,
               round(coalesce(nullif(m->>'work_hours','')::numeric, 0) * 60)::integer),
      coalesce(nullif(m->>'hourly_applied','')::integer, 0),
      coalesce(nullif(m->>'wage_amount','')::integer, 0),
      coalesce(nullif(m->>'back_amount','')::integer, 0),
      coalesce(nullif(m->>'allowance','')::integer, 0),
      coalesce(nullif(m->>'deduction','')::integer, 0),
      coalesce(nullif(m->>'advance','')::integer, 0),
      coalesce(nullif(m->>'net_amount','')::integer,
               coalesce(nullif(m->>'wage_amount','')::integer,0)
             + coalesce(nullif(m->>'back_amount','')::integer,0)
             + coalesce(nullif(m->>'allowance','')::integer,0)
             - coalesce(nullif(m->>'deduction','')::integer,0)
             - coalesce(nullif(m->>'advance','')::integer,0)),
      coalesce(nullif(m->>'nominations','')::integer, 0),
      coalesce(nullif(m->>'douhans','')::integer, 0),
      'confirmed',
      nullif(btrim(coalesce(m->>'note','')),''))
    on conflict (cast_id, period_from, period_to) do update
      set work_minutes   = excluded.work_minutes,
          hourly_applied = excluded.hourly_applied,
          wage_amount    = excluded.wage_amount,
          back_amount    = excluded.back_amount,
          allowance      = excluded.allowance,
          deduction      = excluded.deduction,
          advance        = excluded.advance,
          net_amount     = excluded.net_amount,
          nominations    = excluded.nominations,
          douhans        = excluded.douhans,
          note           = coalesce(excluded.note, public.night_payroll.note)
    returning id into v_id;
    return v_id;
  end if;

  raise exception 'その種類は反映できません';
end;
$$;

create or replace function public.import_apply(p_batch uuid)
returns table (applied integer, failed integer)
language plpgsql security definer set search_path = public, app
as $$
#variable_conflict use_column
declare
  me public.staff; b public.import_batch; r record;
  v_id uuid; a integer := 0; g integer := 0;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '反映は、店長以上の権限が必要です';
  end if;

  select * into b from public.import_batch where id = p_batch;
  if not found then raise exception '取り込みが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if b.status = 'applied' then raise exception 'この取り込みは、もう反映済みです'; end if;
  if b.status = 'canceled' then raise exception 'この取り込みは取り消されています'; end if;

  for r in select * from public.import_row
            where batch_id = p_batch and status = 'ok' order by line_no
  loop
    begin
      v_id := app.import_apply_row(b.kind, b.tenant_id, b.store_id, r.mapped);
      update public.import_row set status = 'applied', target_id = v_id, error = null
       where id = r.id;
      a := a + 1;
    exception when others then
      update public.import_row set status = 'ng', error = SQLERRM where id = r.id;
      g := g + 1;
    end;
  end loop;

  -- 件数は、行の状態から数え直します（確認ではじいた行も残ります）
  update public.import_batch
     set status = case
           when exists (select 1 from public.import_row
                         where batch_id = p_batch and status in ('new','ok','ng'))
             then 'reviewing' else 'applied' end,
         ok_count = (select count(*) from public.import_row
                      where batch_id = p_batch and status = 'applied'),
         ng_count = (select count(*) from public.import_row
                      where batch_id = p_batch and status = 'ng'),
         applied_by = me.id,
         applied_at = case when g = 0 then now() else applied_at end
   where id = p_batch;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (b.tenant_id, b.store_id, me.id, 'import_apply', 'import_batch', b.id::text,
          jsonb_build_object('kind', b.kind, 'applied', a, 'failed', g));

  return query select a, g;
end;
$$;


-- ============================================================================
--  6. 取り消し
--     反映する前なら、取り込みごと消せます。
--     反映したあとは、増えた行を消さずに「取り消し」の印だけ付けます。
--     （売上や給与を勝手に消さないためです。個別の削除は画面からおこないます）
-- ============================================================================
create or replace function public.import_cancel(p_batch uuid, p_reason text default null)
returns public.import_batch
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; b public.import_batch;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '取り消しは、店長以上の権限が必要です';
  end if;

  select * into b from public.import_batch where id = p_batch;
  if not found then raise exception '取り込みが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.import_batch
     set status = case when b.status = 'applied' then 'reverted' else 'canceled' end,
         note = case when p_reason is null or btrim(p_reason) = '' then note
                     else coalesce(note || ' / ', '') || '取消: ' || p_reason end
   where id = p_batch returning * into b;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (b.tenant_id, b.store_id, me.id, 'import_cancel', 'import_batch', b.id::text,
          jsonb_build_object('reason', p_reason, 'was', b.status));
  return b;
end;
$$;


-- ============================================================================
--  7. 画面用
-- ============================================================================
create or replace function public.import_list(p_store uuid, p_limit integer default 30)
returns table (
  id uuid, kind text, source text, file_name text,
  row_count integer, ok_count integer, ng_count integer,
  status text, note text, created_at timestamptz,
  created_name text, files integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  return query
  select b.id, b.kind, b.source, b.file_name,
         b.row_count, b.ok_count, b.ng_count,
         b.status, b.note, b.created_at, s.name,
         (select count(*)::integer from public.import_file f where f.batch_id = b.id)
    from public.import_batch b
    left join public.staff s on s.id = b.created_by
   where b.store_id = p_store
   order by b.created_at desc
   limit greatest(least(coalesce(p_limit,30), 200), 1);
end;
$$;

create or replace function public.import_rows(p_batch uuid, p_status text default null)
returns table (id uuid, line_no integer, mapped jsonb, status text, error text)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare b public.import_batch;
begin
  select * into b from public.import_batch where id = p_batch;
  if not found then raise exception '取り込みが見つかりません'; end if;
  if not app.can_store(b.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select r.id, r.line_no, r.mapped, r.status, r.error
    from public.import_row r
   where r.batch_id = p_batch
     and (p_status is null or r.status = p_status)
   order by r.line_no;
end;
$$;

-- 取り込みできる項目の一覧（画面の見出しと、CSVの雛形に使います）
create or replace function public.import_fields(p_kind text)
returns table (field text, label text, required boolean, sample text)
language sql stable
as $$
  select v.field, v.label, v.required, v.sample from (values
    ('cast','name','源氏名',true,'あや'),
    ('cast','real_name','本名',false,'山田 彩'),
    ('cast','hourly_wage','時給',false,'2500'),
    ('cast','joined_on','入店日',false,'2025-04-01'),
    ('cast','left_on','退店日',false,''),
    ('cast','birthday','生年月日',false,'2002-06-15'),
    ('cast','tel','電話番号',false,'090-0000-0000'),
    ('cast','address','住所',false,'神戸市中央区…'),
    ('cast','email','メール',false,'aya@example.com'),

    ('customer','name','お客様名',true,'田中 様'),
    ('customer','tel','電話番号',false,'090-0000-0000'),
    ('customer','note','メモ',false,'ウイスキー党'),

    ('attendance','cast_name','源氏名',true,'あや'),
    ('attendance','business_date','営業日',true,'2026-08-15'),
    ('attendance','clock_in','出勤',false,'2026-08-15 20:00+09'),
    ('attendance','clock_out','退勤',false,'2026-08-16 01:00+09'),
    ('attendance','late_minutes','遅刻（分）',false,'0'),
    ('attendance','note','メモ',false,''),

    ('payroll','cast_name','源氏名',true,'あや'),
    ('payroll','period_from','対象期間（開始）',true,'2026-08-01'),
    ('payroll','period_to','対象期間（終了）',true,'2026-08-31'),
    ('payroll','work_hours','出勤時間',false,'86.5'),
    ('payroll','wage_amount','時給ぶん',false,'216250'),
    ('payroll','back_amount','バック',false,'48000'),
    ('payroll','allowance','手当',false,'10000'),
    ('payroll','deduction','控除',false,'3000'),
    ('payroll','advance','日払い済み',false,'120000'),
    ('payroll','net_amount','差引支給額',false,'151250'),
    ('payroll','nominations','本指名',false,'12'),
    ('payroll','douhans','同伴',false,'4'),
    ('payroll','note','メモ',false,'')
  ) as v(kind, field, label, required, sample)
  where v.kind = p_kind;
$$;


-- ============================================================================
--  8. 預かったファイルの置き場（Supabase の Storage）
--     imports バケットは、ログインしている人だけが読み書きできます。
--     （Supabase 以外のPostgreSQLでは、ここは自動で飛ばします）
-- ============================================================================
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    execute $q$
      insert into storage.buckets (id, name, public)
      values ('imports','imports',false)
      on conflict (id) do nothing
    $q$;

    execute $q$drop policy if exists p_imports_all on storage.objects$q$;
    execute $q$
      create policy p_imports_all on storage.objects for all
        to authenticated
        using (bucket_id = 'imports')
        with check (bucket_id = 'imports')
    $q$;
  end if;
end $$;


-- ============================================================================
--  9. 行の見せ方（RLS）と権限
-- ============================================================================
alter table public.import_batch enable row level security;
alter table public.import_file  enable row level security;
alter table public.import_row   enable row level security;

drop policy if exists p_import_batch on public.import_batch;
create policy p_import_batch on public.import_batch for all
  using (tenant_id = app.my_tenant() and app.can_store(store_id)
         and app.my_role() in ('owner','manager'))
  with check (tenant_id = app.my_tenant() and app.can_store(store_id)
         and app.my_role() in ('owner','manager'));

do $$
declare t text;
begin
  foreach t in array array['import_file','import_row'] loop
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format(
      'create policy p_%1$s on public.%1$s for all
         using (exists (select 1 from public.import_batch b
                        where b.id = batch_id
                          and b.tenant_id = app.my_tenant()
                          and app.can_store(b.store_id)
                          and app.my_role() in (''owner'',''manager'')))
         with check (exists (select 1 from public.import_batch b
                        where b.id = batch_id
                          and b.tenant_id = app.my_tenant()
                          and app.can_store(b.store_id)
                          and app.my_role() in (''owner'',''manager'')))', t);
  end loop;
end $$;

grant select, insert, update, delete on
  public.import_batch, public.import_file, public.import_row
to authenticated;

grant execute on function
  public.import_create(uuid, text, text, text, text),
  public.import_file_add(uuid, text, text, text, integer, integer),
  public.import_rows_add(uuid, jsonb),
  public.import_row_set(uuid, jsonb, text),
  public.import_check(uuid),
  public.import_apply(uuid),
  public.import_cancel(uuid, text),
  public.import_list(uuid, integer),
  public.import_rows(uuid, text),
  public.import_fields(text)
to authenticated;


-- ============================================================================
--  確認用
--   select * from public.import_fields('payroll');
--   select * from public.import_list('店舗ID');
-- ============================================================================
