-- ============================================================================
--
--   だんどりシリーズ  共通ぶん（017〜027）
--
--   Supabase の SQL Editor に、このファイルの中身をぜんぶ貼って、
--   いちど「Run」を押してください。
--
--   ・すでに1回入れている方も、そのまま貼り直して大丈夫です。
--     中のデータは消えません。しくみだけが新しくなります。
--   ・何度実行しても壊れません。
--
--   ＜入っているもの＞
--     1. シフト希望（募集・本人用リンク・LINEからの提出・承認・確定版の返送）
--     2. 届出・許可証（控えの画像・更新期限・見せる範囲）
--     3. 給与明細の送り先（LINE／メール／手渡し）を、業種をまたいで1か所に
--     4. ★権限★ 月べつの売上・歩合・原価・人件費・本部は店長以上だけ。
--        給与明細は、店長以上は全員ぶん・スタッフはご自分のぶんだけ。
--     5. 画面の見た目（着せ替え）。見せ方4種＋フォント・文字の大きさ・色。
--        人ごとに覚えるので、どの端末で入っても同じ見た目になります。
--     6. ★在庫・発注★ 消耗品・備品の台帳、出し入れ（使った・捨てた・棚卸）、
--        発注点を切ったもののお知らせ、発注書（下書き→発注ずみ→納品）。
--        納品を入れると、在庫が自動でふえます。
--        ナイトだんどり・キャストだんどりの画面から使います。
--     7. ★お店のえらびかた★ 画面に、その業種のお店だけを出します。
--        更新しても、ページを移っても、えらんだお店が入れかわりません。
--     8. ★清掃・やること★ 清掃する場所（業種ごとのひな形つき）、
--        きょうやること、紙のチェック表（ハンコ欄も）、
--        業者さんのクリーニングの年1ご案内。5業種すべてで使えます。
--     9. ★デモのデータ★ 清掃の実施記録・在庫の出し入れ・発注書3枚・
--        書類の期限・シフト希望の受付を、まとめて入れます。
--        商談で、数字だけでなく「ひととおり動くところ」をお見せできます。
--    10. ★ログインの管理★ 店長以上の方が、画面からスタッフを名簿に足し、
--        ログインを作る／作り直す／止める／権限を変える、までできます。
--        ★Edge Function「staff-login」を入れてからお使いください。
--    11. ★日報のなおし★ 日報のエラー（v.guests）をなおしました。
--    12. ★使ってみての直し★
--        ・日報に「その日のひとこと」の欄。AIは、この一言と数字から書きます。
--        ・席の空き（フード）が、いま開いている卓もふくめて出ます。
--          空いている卓をタップすると、その場でお通しできます。
--        ・ペットのお部屋を「あとで決める」に戻せるようにしました。
--        ・デモに「AIの下書きから作った日報」の見本が入ります。
--
--   ＜今回なおしたところ＞
--     ・業種の名簿を引くところを、1か所にまとめました（app.subject_table）。
--       サロンだんどり・ペットだんどりのスタッフも、
--       シフト希望とLINEの登録に出るようになります。
--     ・給与明細の送り先をさがすしくみを、この共通ぶんに移しました。
--       これで、どの業種だけを入れていても動きます。
--     ・権限のふた（019）を足しました。
--     ・在庫・発注（021）を足しました。
--     ・お店が勝手に入れかわるのをなおしました（022）。
--     ・清掃・やること（023）を足しました。
--     ・デモのデータ（024）を足しました。
--     ・ログインの管理（025）を足しました。
--     ・日報のエラー（026）をなおしました。
--     ・使ってみての直し（027）を足しました。
--       ★入れたあと、最後に一度だけ次を実行してください。
--         select * from app.demo_fill_all();
--
--   ＜だいじなこと＞
--     業種のSQL（101〜／201〜／301〜／401〜）を貼り直したあとは、
--     ★このファイルをもう一度貼り直してください。★
--     貼り直すと関数が元にもどり、権限のふたが外れます。
--     このファイルは、外れていたら付け直します。
--
--   株式会社スリーピース / AI伴走LABO
-- ============================================================================



-- ############################################################################
-- #
-- #   1. シフト希望   （017_shift_wish.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通  017_shift_wish.sql
--
--  シフト希望の「提出 → 承認 → 確定を本人に返す」まで
--
--   ・お店が「募集」を開きます（半月ごと／月ごと／週ごと、お店で選べます）
--   ・スタッフは、カレンダーから希望の日をえらびます（何日でも）
--     日ごとに、入れる時間帯もえらべます
--   ・お店が中身を見て、承認するか、ひとこと添えて差し戻します
--   ・承認すると、確定したシフトが本人に返ります
--
--   出し方は3つ。どれで出しても、同じところに入ります。
--     1. お店の端末で、スタッフの代わりに入れる
--     2. 本人用のリンク（LINE・メール・SMSで配れます）を開いて出す
--     3. LINEのトークに文字で送る（例： 10/1 10-17）
--
--  ナイト・キャスト・フードのどれでも同じように使えます。
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  0. お店の設定
-- ============================================================================
-- 募集の単位： half（半月ごと）/ month（月ごと）/ week（週ごと）
alter table public.store add column if not exists wish_cycle text not null default 'half';
-- 締切は「その期間がはじまる何日前か」
alter table public.store add column if not exists wish_deadline_days integer not null default 5;
-- 本人用リンクの入口（Netlifyのアドレス。空なら画面側で補います）
alter table public.store add column if not exists wish_base_url text;

-- お店の連絡先メール。
-- メールを送るときの「返信先」に使います。
-- 明細やシフトのお知らせに返信したとき、お店に届くようにするためのものです。
alter table public.store add column if not exists email text;


-- ============================================================================
--  1. 入れる時間帯のえらびかた（共通）
--
--    「10:00〜17:00」のような、よく使う時間帯をならべておきます。
--    スタッフは、日ごとにここからえらびます。
--    もちろん、時刻を直に入れることもできます。
-- ============================================================================
create table if not exists public.shift_slot (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenant(id) on delete cascade,
  store_id   uuid not null references public.store(id) on delete cascade,
  name       text not null,                 -- 「早番」「遅番」「通し」「夜だけ」
  start_time time not null,
  end_time   time not null,
  color      text,
  sort_no    integer not null default 100,
  is_active  boolean not null default true,
  unique (store_id, name)
);
create index if not exists idx_shift_slot on public.shift_slot(store_id, is_active, sort_no);

-- 時間帯のひな形を入れます。
-- フードのシフトひな形がすでにあれば、それをそのまま写します。
create or replace function app.shift_slot_seed_core(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; n integer; v_food boolean := false;
begin
  select * into st from public.store where id = p_store;

  -- food_shift_pattern はフードにしか無いので、ほかの業種で止まらないよう文字列で実行します
  if to_regclass('public.food_shift_pattern') is not null then
    execute 'select exists (select 1 from public.food_shift_pattern p where p.store_id = $1)'
      into v_food using p_store;
  end if;

  if v_food then
    execute $q$
      insert into public.shift_slot(tenant_id, store_id, name, start_time, end_time, color, sort_no)
      select $1, $2, p.name, p.start_time, p.end_time, p.color, p.sort_no
        from public.food_shift_pattern p
       where p.store_id = $2 and p.is_active
         and not exists (select 1 from public.shift_slot x
                          where x.store_id = $2 and x.name = p.name)
    $q$ using st.tenant_id, p_store;
  else
    insert into public.shift_slot(tenant_id, store_id, name, start_time, end_time, sort_no)
    select st.tenant_id, p_store, v.name, v.s::time, v.e::time, v.sort
      from (values
        ('早番',   '10:00', '17:00', 10),
        ('遅番',   '16:00', '23:30', 20),
        ('通し',   '10:00', '23:30', 30),
        ('夜だけ', '19:00', '01:00', 40)
      ) as v(name, s, e, sort)
     where not exists (select 1 from public.shift_slot x
                        where x.store_id = p_store and x.name = v.name);
  end if;

  select count(*)::integer into n from public.shift_slot
   where store_id = p_store and is_active;
  return n;
end;
$$;

create or replace function public.shift_slot_seed(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception 'はじめの設定は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  return app.shift_slot_seed_core(p_store);
end;
$$;

revoke all on function app.shift_slot_seed_core(uuid) from anon, authenticated;

create or replace function public.shift_slot_save(
  p_store uuid, p_id uuid default null, p_name text default null,
  p_start time default null, p_end time default null,
  p_color text default null, p_sort integer default null,
  p_active boolean default null)
returns public.shift_slot
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; r public.shift_slot;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '時間帯を直すには、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p_store;

  if p_id is null then
    if nullif(btrim(coalesce(p_name, '')), '') is null then
      raise exception '時間帯の名前を入れてください';
    end if;
    if p_start is null or p_end is null then
      raise exception 'はじめと終わりの時刻を入れてください';
    end if;
    insert into public.shift_slot(
      tenant_id, store_id, name, start_time, end_time, color, sort_no)
    values (st.tenant_id, p_store, btrim(p_name), p_start, p_end, p_color,
            coalesce(p_sort, 100))
    returning * into r;
  else
    update public.shift_slot
       set name       = coalesce(nullif(btrim(coalesce(p_name,'')),''), name),
           start_time = coalesce(p_start, start_time),
           end_time   = coalesce(p_end, end_time),
           color      = coalesce(p_color, color),
           sort_no    = coalesce(p_sort, sort_no),
           is_active  = coalesce(p_active, is_active)
     where id = p_id and store_id = p_store returning * into r;
    if not found then raise exception 'その時間帯はありません'; end if;
  end if;
  return r;
end;
$$;


-- ============================================================================
--  2. 募集（この期間ぶんの希望を出してください、というまとまり）
-- ============================================================================
create table if not exists public.shift_period (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant(id) on delete cascade,
  store_id    uuid not null references public.store(id) on delete cascade,
  kind        text not null default 'half',      -- half / month / week
  period_from date not null,
  period_to   date not null,
  deadline_at timestamptz,
  status      text not null default 'open',      -- open（受付中）/ closed（締切）/ fixed（確定ずみ）
  note        text,
  created_by  uuid references public.staff(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (store_id, period_from, period_to)
);
create index if not exists idx_shift_period on public.shift_period(store_id, period_from desc);

-- 曜日を日本語で出します
create or replace function app.dow_ja(p_date date)
returns text
language sql immutable
as $$
  select ('{日,月,火,水,木,金,土}'::text[])[extract(dow from p_date)::integer + 1]
$$;

-- その日をふくむ期間の、はじめと終わりを出します
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

-- つぎの募集を開きます（何も指定しなければ、つぎの期間を自動で作ります）
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
  if me.role not in ('owner','manager') then
    raise exception '募集を開くには、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p_store;

  v_kind := coalesce(nullif(p_kind, ''), st.wish_cycle, 'half');
  if v_kind not in ('half','month','week') then
    raise exception '募集の単位は、半月・月・週 のどれかです';
  end if;

  -- 指定がなければ、いまの期間のつぎを作ります
  if p_anchor is not null then
    v_anchor := p_anchor;
  else
    select w.period_to + 1 into v_anchor from app.wish_range(v_kind, current_date) w;
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

  -- 時間帯のひな形がまだなら、入れておきます
  if not exists (select 1 from public.shift_slot s where s.store_id = p_store) then
    perform app.shift_slot_seed_core(p_store);
  end if;

  return r;
end;
$$;

create or replace function public.shift_period_status(p_period uuid, p_status text)
returns public.shift_period
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; r public.shift_period;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '募集を変えるには、店長以上の権限が必要です';
  end if;
  select * into r from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(r.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if p_status not in ('open','closed','fixed') then
    raise exception 'その状態にはできません';
  end if;

  update public.shift_period set status = p_status where id = p_period returning * into r;
  return r;
end;
$$;

create or replace function public.shift_period_list(p_store uuid, p_limit integer default 12)
returns table (
  id uuid, kind text, kind_label text,
  period_from date, period_to date, deadline_at timestamptz,
  status text, status_label text,
  people integer, submitted integer, approved integer, note text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select p.id, p.kind,
         case p.kind when 'half' then '半月ごと' when 'month' then '月ごと'
                     when 'week' then '週ごと' else p.kind end,
         p.period_from, p.period_to, p.deadline_at, p.status,
         case p.status when 'open' then '受付中' when 'closed' then '締切'
                       when 'fixed' then '確定ずみ' else p.status end,
         coalesce(w.n, 0), coalesce(w.sub, 0), coalesce(w.app, 0), p.note
    from public.shift_period p
    left join lateral (
      select count(*)::integer as n,
             count(*) filter (where x.status in ('submitted','approved'))::integer as sub,
             count(*) filter (where x.status = 'approved')::integer as app
        from public.shift_wish x where x.period_id = p.id
    ) w on true
   where p.store_id = p_store
   order by p.period_from desc
   limit coalesce(p_limit, 12);
end;
$$;


-- ============================================================================
--  3. 希望の束（だれの、どの期間ぶんか）
-- ============================================================================
create table if not exists public.shift_wish (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  period_id     uuid not null references public.shift_period(id) on delete cascade,
  subject_kind  text not null,                 -- food_staff / night_cast / cast_member
  subject_id    uuid not null,
  subject_name  text not null,
  status        text not null default 'draft', -- draft / submitted / approved / returned
  source        text not null default 'staff', -- staff（お店の端末）/ link（本人用リンク）/ line
  token         text unique,                   -- 本人用リンクの合いことば
  token_until   timestamptz,
  submitted_at  timestamptz,
  approved_at   timestamptz,
  approved_by   uuid references public.staff(id) on delete set null,
  reply_note    text,                          -- 差し戻しのときの、ひとこと
  note          text,                          -- 本人からのひとこと
  updated_at    timestamptz not null default now(),
  unique (period_id, subject_kind, subject_id)
);
create index if not exists idx_shift_wish on public.shift_wish(store_id, period_id, status);

create table if not exists public.shift_wish_day (
  id            uuid primary key default gen_random_uuid(),
  wish_id       uuid not null references public.shift_wish(id) on delete cascade,
  business_date date not null,
  kind          text not null default 'ok',    -- ok（入れます）/ want（入りたい）/ ng（休みたい）
  slot_id       uuid references public.shift_slot(id) on delete set null,
  from_time     time,
  to_time       time,
  note          text,
  unique (wish_id, business_date)
);
create index if not exists idx_shift_wish_day on public.shift_wish_day(wish_id, business_date);


-- 種類から、名簿の表を引きます。
--   業種が増えたときは、ここに1行足すだけで、ぜんぶに効きます。
create or replace function app.subject_table(p_kind text)
returns text
language sql immutable
as $$
  select case p_kind
           when 'food_staff'  then 'public.food_staff'
           when 'night_cast'  then 'public.night_cast'
           when 'cast_member' then 'public.cast_member'
           when 'salon_staff' then 'public.salon_staff'
           when 'pet_staff'   then 'public.pet_staff'
           else null end;
$$;

-- 名簿から、その方の名前を引きます（業種はなんでもかまいません）
create or replace function app.subject_name(p_kind text, p_id uuid)
returns text
language plpgsql stable security definer set search_path = public, app
as $$
declare v_tbl text; v_name text;
begin
  v_tbl := app.subject_table(p_kind);
  if v_tbl is null or to_regclass(v_tbl) is null then return null; end if;
  execute format('select c.name from %s c where c.id = $1', v_tbl) into v_name using p_id;
  return v_name;
end;
$$;

-- そのお店で働く方を、業種を問わずならべます
create or replace function public.shift_people(p_store uuid)
returns table (subject_kind text, subject_id uuid, name text, job_label text)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;

  if to_regclass('public.food_staff') is not null then
    return query execute $q$
      select 'food_staff'::text, f.id, f.name,
             case f.job when 'hall' then 'ホール' when 'kitchen' then 'キッチン'
                        when 'manager' then '社員' else f.job end
        from public.food_staff f
       where f.store_id = $1 and f.is_active
       order by f.sort_no, f.name
    $q$ using p_store;
  end if;

  if to_regclass('public.cast_member') is not null then
    return query execute $q$
      select 'cast_member'::text, c.id, c.name, 'キャスト'::text
        from public.cast_member c
       where c.store_id = $1 and c.is_active
       order by c.name
    $q$ using p_store;
  end if;

  if to_regclass('public.night_cast') is not null then
    return query execute $q$
      select 'night_cast'::text, c.id, c.name, 'キャスト'::text
        from public.night_cast c
       where c.store_id = $1 and c.is_active
       order by c.name
    $q$ using p_store;
  end if;

  if to_regclass('public.salon_staff') is not null then
    return query execute $q$
      select 'salon_staff'::text, x.id, x.name,
             case x.job when 'stylist' then 'スタイリスト'
                        when 'assistant' then 'アシスタント'
                        when 'eyelash' then 'まつげ' when 'nail' then 'ネイル'
                        when 'esthe' then 'エステ' else 'そのほか' end
        from public.salon_staff x
       where x.store_id = $1 and x.is_active
       order by x.sort_no, x.name
    $q$ using p_store;
  end if;

  if to_regclass('public.pet_staff') is not null then
    return query execute $q$
      select 'pet_staff'::text, x.id, x.name,
             case x.job when 'trimmer' then 'トリマー'
                        when 'care' then 'お世話' when 'driver' then '送迎'
                        else 'そのほか' end
        from public.pet_staff x
       where x.store_id = $1 and x.is_active
       order by x.sort_no, x.name
    $q$ using p_store;
  end if;
end;
$$;


-- 希望の束を、なければ作ります（お店の端末からでも、リンクからでも、同じものを使います）
create or replace function app.wish_get_or_make(
  p_period uuid, p_kind text, p_id uuid, p_source text default 'staff')
returns public.shift_wish
language plpgsql security definer set search_path = public, app
as $$
declare p public.shift_period; w public.shift_wish; v_name text;
begin
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;

  select * into w from public.shift_wish
   where period_id = p_period and subject_kind = p_kind and subject_id = p_id;
  if found then return w; end if;

  v_name := coalesce(app.subject_name(p_kind, p_id), '（お名前なし）');

  insert into public.shift_wish(
    tenant_id, store_id, period_id, subject_kind, subject_id, subject_name, source)
  values (p.tenant_id, p.store_id, p_period, p_kind, p_id, v_name, p_source)
  returning * into w;
  return w;
end;
$$;


-- ============================================================================
--  4. 本人用リンク
--
--    合いことばだけで開けるページのアドレスを作ります。
--    LINEでもメールでもSMSでも、そのまま送れます。
-- ============================================================================
create or replace function public.wish_link(
  p_period uuid, p_kind text, p_id uuid, p_base text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; p public.shift_period; w public.shift_wish;
  st public.store; v_tok text; v_url text;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p.store_id;

  w := app.wish_get_or_make(p_period, p_kind, p_id, 'link');

  if w.token is null or coalesce(w.token_until, now()) < now() then
    v_tok := md5(random()::text || clock_timestamp()::text || w.id::text)
           || md5(random()::text || clock_timestamp()::text);
    update public.shift_wish
       set token = v_tok,
           token_until = (p.period_to + 14) + time '23:59'
     where id = w.id returning * into w;
  end if;

  v_url := coalesce(nullif(p_base, ''), nullif(st.wish_base_url, ''), '')
        || 'wish.html?t=' || w.token;

  return jsonb_build_object(
    'wish_id', w.id,
    'name', w.subject_name,
    'token', w.token,
    'url', v_url,
    'period_from', p.period_from,
    'period_to', p.period_to,
    'deadline_at', p.deadline_at,
    'message',
      w.subject_name || ' さん' || E'\n\n' ||
      to_char(p.period_from, 'FMMM月FMDD日') || '〜' || to_char(p.period_to, 'FMMM月FMDD日') ||
      ' のシフト希望をお願いします。' || E'\n' ||
      case when p.deadline_at is null then ''
           else '締切： ' ||
                to_char(p.deadline_at at time zone 'Asia/Tokyo', 'FMMM月FMDD日 HH24:MI')
                || E'\n' end ||
      E'\n' || v_url || E'\n\n' ||
      'カレンダーから、入れる日をえらんでください。' || E'\n' ||
      coalesce(st.name, ''));
end;
$$;

-- 期間ぶん、みんなのリンクをまとめて出します（配るとき用）
create or replace function public.wish_link_all(p_period uuid, p_base text default null)
returns table (subject_kind text, subject_id uuid, name text, status text, url text, message text)
language plpgsql security definer set search_path = public, app
as $$
#variable_conflict use_column
declare p public.shift_period; r record; j jsonb;
begin
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  for r in select * from public.shift_people(p.store_id) loop
    j := public.wish_link(p_period, r.subject_kind, r.subject_id, p_base);
    return query
      select r.subject_kind, r.subject_id, r.name,
             coalesce((select w.status from public.shift_wish w
                        where w.period_id = p_period
                          and w.subject_kind = r.subject_kind
                          and w.subject_id = r.subject_id), 'draft'),
             j->>'url', j->>'message';
  end loop;
end;
$$;


-- ============================================================================
--  5. お客様…ではなく「本人」の画面（ログインしません）
--
--    合いことばがないと、何も返しません。
--    見えるのは、ご自分の希望と、ご自分の確定シフトだけです。
-- ============================================================================
create or replace function public.wish_open(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare w public.shift_wish; p public.shift_period; st public.store;
begin
  select * into w from public.shift_wish where token = p_token;
  if not found then
    raise exception 'このリンクは、いまお使いいただけません。お店にご連絡ください';
  end if;
  if coalesce(w.token_until, now() + interval '1 day') < now() then
    raise exception 'このリンクは期限が切れています。お店にご連絡ください';
  end if;

  select * into p from public.shift_period where id = w.period_id;
  select * into st from public.store where id = w.store_id;

  return jsonb_build_object(
    'name', w.subject_name,
    'store_name', st.name,
    'status', w.status,
    'status_label', case w.status
                      when 'draft' then 'まだ出していません'
                      when 'submitted' then '出しました（確認まちです）'
                      when 'approved' then '確定しました'
                      when 'returned' then '戻ってきています'
                      else w.status end,
    'reply_note', w.reply_note,
    'note', w.note,
    'period_from', p.period_from,
    'period_to', p.period_to,
    'deadline_at', p.deadline_at,
    'past_deadline', (p.deadline_at is not null and p.deadline_at < now()),
    'period_status', p.status,
    'can_edit', (w.status in ('draft','returned') and p.status = 'open'),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'name', s.name,
               'from', to_char(s.start_time, 'HH24:MI'),
               'to',   to_char(s.end_time,   'HH24:MI'),
               'color', s.color) order by s.sort_no)
        from public.shift_slot s
       where s.store_id = w.store_id and s.is_active), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
               'date', d.business_date, 'kind', d.kind,
               'slot_id', d.slot_id,
               'from', to_char(d.from_time, 'HH24:MI'),
               'to',   to_char(d.to_time,   'HH24:MI'),
               'note', d.note) order by d.business_date)
        from public.shift_wish_day d where d.wish_id = w.id), '[]'::jsonb),
    'fixed', app.wish_fixed_days(w.subject_kind, w.subject_id, p.period_from, p.period_to));
end;
$$;

-- 希望を保存します（まだ提出ではありません）
create or replace function public.wish_set(p_token text, p_days jsonb, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare w public.shift_wish; p public.shift_period; r jsonb; v_date date; n integer := 0;
begin
  select * into w from public.shift_wish where token = p_token;
  if not found then
    raise exception 'このリンクは、いまお使いいただけません。お店にご連絡ください';
  end if;
  if coalesce(w.token_until, now() + interval '1 day') < now() then
    raise exception 'このリンクは期限が切れています。お店にご連絡ください';
  end if;

  select * into p from public.shift_period where id = w.period_id;
  if p.status <> 'open' then
    raise exception 'この期間の受付は、もう終わっています。お店にご連絡ください';
  end if;
  if w.status = 'approved' then
    raise exception 'もう確定しています。変えたいときは、お店にご連絡ください';
  end if;

  if p_days is null or jsonb_typeof(p_days) <> 'array' then
    raise exception '希望の日をえらんでください';
  end if;

  delete from public.shift_wish_day where wish_id = w.id;

  for r in select * from jsonb_array_elements(p_days) loop
    v_date := (r->>'date')::date;
    if v_date is null or v_date < p.period_from or v_date > p.period_to then
      continue;
    end if;
    insert into public.shift_wish_day(
      wish_id, business_date, kind, slot_id, from_time, to_time, note)
    values (w.id, v_date,
            coalesce(nullif(r->>'kind', ''), 'ok'),
            nullif(r->>'slot_id', '')::uuid,
            nullif(r->>'from', '')::time,
            nullif(r->>'to', '')::time,
            nullif(btrim(coalesce(r->>'note', '')), ''))
    on conflict (wish_id, business_date) do nothing;
    n := n + 1;
  end loop;

  update public.shift_wish
     set note = coalesce(p_note, note),
         status = case when status = 'returned' then 'draft' else status end,
         updated_at = now()
   where id = w.id;

  return jsonb_build_object('ok', true, 'count', n,
    'message', n || '日ぶん、控えました。よろしければ「提出する」を押してください');
end;
$$;

create or replace function public.wish_submit(p_token text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare w public.shift_wish; p public.shift_period; n integer;
begin
  select * into w from public.shift_wish where token = p_token;
  if not found then
    raise exception 'このリンクは、いまお使いいただけません。お店にご連絡ください';
  end if;
  select * into p from public.shift_period where id = w.period_id;
  if p.status <> 'open' then
    raise exception 'この期間の受付は、もう終わっています。お店にご連絡ください';
  end if;

  select count(*)::integer into n from public.shift_wish_day where wish_id = w.id;
  if n = 0 then raise exception '日にちがえらばれていません'; end if;

  update public.shift_wish
     set status = 'submitted', submitted_at = now(),
         note = coalesce(p_note, note), reply_note = null, updated_at = now()
   where id = w.id;

  return jsonb_build_object('ok', true, 'count', n,
    'message', 'お店に送りました。確定したら、またこのページに出ます');
end;
$$;

-- 確定したシフトを見る（本人）
create or replace function public.wish_fixed(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare w public.shift_wish; p public.shift_period;
begin
  select * into w from public.shift_wish where token = p_token;
  if not found then
    raise exception 'このリンクは、いまお使いいただけません。お店にご連絡ください';
  end if;
  select * into p from public.shift_period where id = w.period_id;

  return jsonb_build_object(
    'name', w.subject_name,
    'status', w.status,
    'period_from', p.period_from,
    'period_to', p.period_to,
    'days', app.wish_fixed_days(w.subject_kind, w.subject_id, p.period_from, p.period_to));
end;
$$;


-- ============================================================================
--  6. 確定したシフトの置き場
--
--    フードは、すでにある food_shift をそのまま使います。
--    ナイト・キャストは、この shift_plan を使います。
--    どちらに入っていても、同じ形で読み出せます。
-- ============================================================================
create table if not exists public.shift_plan (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  business_date date not null,
  subject_kind  text not null,
  subject_id    uuid not null,
  subject_name  text not null,
  slot_id       uuid references public.shift_slot(id) on delete set null,
  slot_name     text,
  from_time     time not null,
  to_time       time not null,
  note          text,
  created_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (store_id, business_date, subject_kind, subject_id)
);
create index if not exists idx_shift_plan on public.shift_plan(store_id, business_date);

-- 確定ぶんを、業種を問わず同じ形で返します
create or replace function app.wish_fixed_days(
  p_kind text, p_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare j jsonb;
begin
  if p_kind = 'food_staff' and to_regclass('public.food_shift') is not null then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object(
               'date', s.business_date,
               'name', pt.name,
               'from', to_char(s.start_at at time zone 'Asia/Tokyo', 'HH24:MI'),
               'to',   to_char(s.end_at   at time zone 'Asia/Tokyo', 'HH24:MI'),
               'break_min', s.break_min,
               'note', s.note) order by s.business_date), '[]'::jsonb)
        from public.food_shift s
        left join public.food_shift_pattern pt on pt.id = s.pattern_id
       where s.food_staff_id = $1 and s.business_date between $2 and $3
         and s.status = 'fixed'
    $q$ into j using p_id, p_from, p_to;
    return coalesce(j, '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'date', x.business_date,
           'name', x.slot_name,
           'from', to_char(x.from_time, 'HH24:MI'),
           'to',   to_char(x.to_time,   'HH24:MI'),
           'note', x.note) order by x.business_date), '[]'::jsonb)
    into j
    from public.shift_plan x
   where x.subject_kind = p_kind and x.subject_id = p_id
     and x.business_date between p_from and p_to;
  return coalesce(j, '[]'::jsonb);
end;
$$;


-- ============================================================================
--  7. お店の画面（承認・差し戻し・確定）
-- ============================================================================
-- 提出のようす（だれが出した／まだか）
create or replace function public.wish_board(p_period uuid)
returns table (
  wish_id uuid, subject_kind text, subject_id uuid, name text, job_label text,
  status text, status_label text, source text, source_label text,
  days integer, ng_days integer, submitted_at timestamptz,
  note text, reply_note text, has_link boolean, warn text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare p public.shift_period;
begin
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select w.id, pe.subject_kind, pe.subject_id, pe.name, pe.job_label,
         coalesce(w.status, 'draft'),
         case coalesce(w.status, 'draft')
           when 'draft' then 'まだです' when 'submitted' then '出ています'
           when 'approved' then '確定ずみ' when 'returned' then '差し戻し中'
           else w.status end,
         coalesce(w.source, 'staff'),
         case coalesce(w.source, 'staff')
           when 'staff' then 'お店で入力' when 'link' then '本人のリンク'
           when 'line' then 'LINE' else w.source end,
         coalesce(d.n, 0), coalesce(d.ng, 0), w.submitted_at,
         w.note, w.reply_note, (w.token is not null),
         nullif(concat_ws(' / ',
           case when coalesce(w.status, 'draft') = 'draft'
                 and p.deadline_at is not null and p.deadline_at < now()
                then '締切をすぎましたが、まだ出ていません' end,
           case when coalesce(d.n, 0) = 0 and coalesce(w.status,'draft') <> 'draft'
                then '日にちがえらばれていません' end
         ), '')
    from public.shift_people(p.store_id) pe
    left join public.shift_wish w
      on w.period_id = p_period and w.subject_kind = pe.subject_kind
     and w.subject_id = pe.subject_id
    left join lateral (
      select count(*)::integer as n,
             count(*) filter (where x.kind = 'ng')::integer as ng
        from public.shift_wish_day x where x.wish_id = w.id
    ) d on true
   order by
     case coalesce(w.status, 'draft')
       when 'submitted' then 1 when 'returned' then 2
       when 'draft' then 3 else 4 end,
     pe.name;
end;
$$;

-- 1人ぶんの中身
create or replace function public.wish_detail(p_wish uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare w public.shift_wish; p public.shift_period;
begin
  select * into w from public.shift_wish where id = p_wish;
  if not found then raise exception 'その希望はありません'; end if;
  if not app.can_store(w.store_id) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into p from public.shift_period where id = w.period_id;

  return jsonb_build_object(
    'wish_id', w.id,
    'name', w.subject_name,
    'subject_kind', w.subject_kind,
    'subject_id', w.subject_id,
    'status', w.status,
    'source', w.source,
    'note', w.note,
    'reply_note', w.reply_note,
    'period_from', p.period_from,
    'period_to', p.period_to,
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
               'date', d.business_date, 'kind', d.kind,
               'slot_id', d.slot_id,
               'slot_name', s.name,
               'from', to_char(coalesce(d.from_time, s.start_time), 'HH24:MI'),
               'to',   to_char(coalesce(d.to_time,   s.end_time),   'HH24:MI'),
               'note', d.note) order by d.business_date)
        from public.shift_wish_day d
        left join public.shift_slot s on s.id = d.slot_id
       where d.wish_id = w.id), '[]'::jsonb),
    'fixed', app.wish_fixed_days(w.subject_kind, w.subject_id, p.period_from, p.period_to));
end;
$$;

-- お店の端末から、代わりに入れる
create or replace function public.wish_set_by_staff(
  p_period uuid, p_kind text, p_id uuid, p_days jsonb, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; p public.shift_period; w public.shift_wish;
  r jsonb; v_date date; n integer := 0;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  w := app.wish_get_or_make(p_period, p_kind, p_id, 'staff');

  delete from public.shift_wish_day where wish_id = w.id;

  for r in select * from jsonb_array_elements(coalesce(p_days, '[]'::jsonb)) loop
    v_date := (r->>'date')::date;
    if v_date is null or v_date < p.period_from or v_date > p.period_to then continue; end if;
    insert into public.shift_wish_day(
      wish_id, business_date, kind, slot_id, from_time, to_time, note)
    values (w.id, v_date,
            coalesce(nullif(r->>'kind', ''), 'ok'),
            nullif(r->>'slot_id', '')::uuid,
            nullif(r->>'from', '')::time,
            nullif(r->>'to', '')::time,
            nullif(btrim(coalesce(r->>'note', '')), ''))
    on conflict (wish_id, business_date) do nothing;
    n := n + 1;
  end loop;

  update public.shift_wish
     set status = case when status = 'approved' then 'approved' else 'submitted' end,
         submitted_at = coalesce(submitted_at, now()),
         note = coalesce(p_note, note), updated_at = now()
   where id = w.id;

  return jsonb_build_object('ok', true, 'wish_id', w.id, 'count', n);
end;
$$;

-- 承認する（希望を、確定シフトに流しこみます）
create or replace function public.wish_approve(p_wish uuid, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; w public.shift_wish; p public.shift_period; st public.store;
  r record; n integer := 0; v_f time; v_t time; v_name text;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '承認は、店長以上の権限が必要です';
  end if;
  select * into w from public.shift_wish where id = p_wish;
  if not found then raise exception 'その希望はありません'; end if;
  if not app.can_store(w.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into p from public.shift_period where id = w.period_id;
  select * into st from public.store where id = w.store_id;

  for r in
    select d.*, s.name as slot_name, s.start_time, s.end_time
      from public.shift_wish_day d
      left join public.shift_slot s on s.id = d.slot_id
     where d.wish_id = p_wish and d.kind in ('ok','want')
     order by d.business_date
  loop
    v_f := coalesce(r.from_time, r.start_time);
    v_t := coalesce(r.to_time,   r.end_time);
    if v_f is null or v_t is null then continue; end if;
    v_name := coalesce(r.slot_name, to_char(v_f, 'HH24:MI') || '〜');

    if w.subject_kind = 'food_staff'
       and to_regprocedure('public.food_shift_set(uuid,date,uuid,uuid,time,time,integer,text,text)')
           is not null then
      -- フードは、もともとのシフト表に入れます
      execute 'select public.food_shift_set($1,$2,$3,null,$4,$5,null,null,$6)'
        using w.store_id, r.business_date, w.subject_id, v_f, v_t, r.note;
    else
      insert into public.shift_plan(
        tenant_id, store_id, business_date, subject_kind, subject_id, subject_name,
        slot_id, slot_name, from_time, to_time, note, created_by)
      values (w.tenant_id, w.store_id, r.business_date, w.subject_kind, w.subject_id,
              w.subject_name, r.slot_id, v_name, v_f, v_t, r.note, me.id)
      on conflict (store_id, business_date, subject_kind, subject_id) do update
        set slot_id = excluded.slot_id, slot_name = excluded.slot_name,
            from_time = excluded.from_time, to_time = excluded.to_time,
            note = excluded.note;
    end if;
    n := n + 1;
  end loop;

  -- フードは、確定の印もつけておきます
  if w.subject_kind = 'food_staff' and to_regclass('public.food_shift') is not null then
    execute 'update public.food_shift set status = ''fixed''
              where store_id = $1 and food_staff_id = $2
                and business_date between $3 and $4'
      using w.store_id, w.subject_id, p.period_from, p.period_to;
  end if;

  update public.shift_wish
     set status = 'approved', approved_at = now(), approved_by = me.id,
         reply_note = p_note, updated_at = now()
   where id = p_wish;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (w.tenant_id, w.store_id, me.id, 'wish_approve', 'shift_wish', p_wish::text,
          jsonb_build_object('name', w.subject_name, 'days', n));

  return jsonb_build_object('ok', true, 'days', n,
    'message', w.subject_name || ' さんのシフトを確定しました（' || n || '日）');
end;
$$;

-- 差し戻す（ひとこと添えて、本人に返します）
create or replace function public.wish_return(p_wish uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; w public.shift_wish;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '差し戻しは、店長以上の権限が必要です';
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'どう直してほしいかを、ひとこと書いてください';
  end if;
  select * into w from public.shift_wish where id = p_wish;
  if not found then raise exception 'その希望はありません'; end if;
  if not app.can_store(w.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.shift_wish
     set status = 'returned', reply_note = btrim(p_note), updated_at = now()
   where id = p_wish;

  return jsonb_build_object('ok', true,
    'message', w.subject_name || ' さんに差し戻しました');
end;
$$;

-- 確定版を本人に送る（LINE／メール。送信は、いつもの送信箱に入ります）
create or replace function public.wish_send(p_wish uuid, p_method text default null, p_base text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; w public.shift_wish; p public.shift_period; st public.store;
  c jsonb; v_method text; v_to text; v_body text; v_days jsonb; v_line text; j jsonb;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '送るのは、店長以上の権限が必要です';
  end if;
  select * into w from public.shift_wish where id = p_wish;
  if not found then raise exception 'その希望はありません'; end if;
  if not app.can_store(w.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into p from public.shift_period where id = w.period_id;
  select * into st from public.store where id = w.store_id;

  c := app.payslip_contact(w.subject_kind, w.subject_id);
  v_method := coalesce(nullif(p_method, ''),
                       case when c->>'line' is not null then 'line'
                            when c->>'mail' is not null then 'email'
                            else 'print' end);

  v_days := app.wish_fixed_days(w.subject_kind, w.subject_id, p.period_from, p.period_to);

  v_line := '';
  if jsonb_array_length(v_days) = 0 then
    v_line := '（この期間のシフトは入っていません）';
  else
    select string_agg(
      to_char((x->>'date')::date, 'FMMM/FMDD') ||
      '（' || app.dow_ja((x->>'date')::date) || '）　' ||
      coalesce(x->>'from', '') || '〜' || coalesce(x->>'to', '') ||
      case when coalesce(x->>'name','') = '' then '' else '　' || (x->>'name') end,
      E'\n' order by (x->>'date')::date)
      into v_line
      from jsonb_array_elements(v_days) x;
  end if;

  v_body :=
    w.subject_name || ' さん' || E'\n\n' ||
    to_char(p.period_from, 'FMMM月FMDD日') || '〜' || to_char(p.period_to, 'FMMM月FMDD日') ||
    ' のシフトが確定しました。' || E'\n\n' || v_line || E'\n\n' ||
    case when w.reply_note is null then '' else w.reply_note || E'\n\n' end ||
    coalesce(st.name, '') ||
    case when st.tel is null then '' else E'\n' || st.tel end;

  if v_method = 'print' then
    return jsonb_build_object('ok', true, 'method', 'print', 'body', v_body,
      'message', '印刷して、お渡しください');
  end if;

  v_to := case v_method when 'line' then c->>'line' else c->>'mail' end;
  if v_to is null then
    raise exception '%の送り先が登録されていません。名簿で登録してください',
      case v_method when 'line' then 'LINE' else 'メール' end;
  end if;

  insert into public.outbox(
    tenant_id, store_id, channel, to_addr, subject, body,
    related_kind, related_id, created_by)
  values (w.tenant_id, w.store_id, v_method, v_to,
          'シフトが確定しました（' || to_char(p.period_from, 'FMMM月FMDD日') || '〜）',
          v_body, 'shift_wish', w.id, me.id);

  return jsonb_build_object('ok', true, 'method', v_method,
    'message', '送信箱に入れました');
end;
$$;

-- まだ出していない方に、催促を送ります
create or replace function public.wish_remind(p_period uuid, p_base text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; p public.shift_period; r record;
  c jsonb; j jsonb; v_to text; v_ch text; n integer := 0; sk integer := 0;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '催促を送るのは、店長以上の権限が必要です';
  end if;
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  for r in
    select * from public.wish_board(p_period)
     where status in ('draft','returned')
  loop
    c := app.payslip_contact(r.subject_kind, r.subject_id);
    v_ch := case when c->>'line' is not null then 'line'
                 when c->>'mail' is not null then 'email' else null end;
    if v_ch is null then sk := sk + 1; continue; end if;
    v_to := case v_ch when 'line' then c->>'line' else c->>'mail' end;

    j := public.wish_link(p_period, r.subject_kind, r.subject_id, p_base);

    insert into public.outbox(
      tenant_id, store_id, channel, to_addr, subject, body,
      related_kind, related_id, created_by)
    values (p.tenant_id, p.store_id, v_ch, v_to,
            'シフト希望のお願い（' || to_char(p.period_from, 'FMMM月FMDD日') || '〜）',
            j->>'message', 'shift_wish', (j->>'wish_id')::uuid, me.id);
    n := n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'queued', n, 'skipped', sk,
    'message', case when n = 0 then '送れる相手がいませんでした'
                    else n || '件を送信箱に入れました' end);
end;
$$;

-- 期間ぜんぶの、日ごとの人数（シフトを組むときの目安）
create or replace function public.wish_day_count(p_period uuid)
returns table (
  business_date date, dow text, ok_count integer, want_count integer,
  ng_count integer, names text, warn text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare p public.shift_period;
begin
  select * into p from public.shift_period where id = p_period;
  if not found then raise exception 'その募集はありません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を見る権限がありません'; end if;

  return query
  select d.d::date, app.dow_ja(d.d::date),
         coalesce(x.ok, 0), coalesce(x.want, 0), coalesce(x.ng, 0),
         x.names,
         case when coalesce(x.ok, 0) + coalesce(x.want, 0) = 0
              then 'この日、入れる人がいません' end
    from generate_series(p.period_from, p.period_to, interval '1 day') as d(d)
    left join lateral (
      select count(*) filter (where wd.kind = 'ok')::integer as ok,
             count(*) filter (where wd.kind = 'want')::integer as want,
             count(*) filter (where wd.kind = 'ng')::integer as ng,
             string_agg(w.subject_name, '、')
               filter (where wd.kind in ('ok','want')) as names
        from public.shift_wish_day wd
        join public.shift_wish w on w.id = wd.wish_id
       where w.period_id = p_period and wd.business_date = d.d::date
         and w.status in ('submitted','approved')
    ) x on true
   order by d.d;
end;
$$;


-- ============================================================================
--  8. LINEのトークに文字で送ってもらう場合
--
--    「10/1 10-17」「10/2 休」のように送られた文を読み取ります。
--    読み取れた日だけ入れて、読み取れなかった行はそのまま返します。
--    （Edge Function の line-webhook から呼ばれます）
-- ============================================================================
create or replace function public.wish_from_line(
  p_line_user_id text, p_text text)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare
  v_kind text; v_id uuid; v_store uuid; v_name text;
  p public.shift_period; w public.shift_wish;
  v_line text; v_lines text[]; v_md text[]; v_hm text[];
  v_date date; v_from time; v_to time; v_wkind text;
  n integer := 0; bad text := ''; v_y integer;
begin
  if nullif(btrim(coalesce(p_line_user_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'reply',
      '申しわけありません。お店に直接ご連絡ください。');
  end if;

  -- だれの LINE かを、名簿からさがします
  if to_regclass('public.food_staff') is not null then
    execute 'select ''food_staff'', f.id, f.store_id, f.name from public.food_staff f
              where f.line_user_id = $1 and f.is_active limit 1'
      into v_kind, v_id, v_store, v_name using p_line_user_id;
  end if;
  if v_id is null and to_regclass('public.cast_member') is not null then
    execute 'select ''cast_member'', c.id, c.store_id, c.name from public.cast_member c
              where c.line_user_id = $1 and c.is_active limit 1'
      into v_kind, v_id, v_store, v_name using p_line_user_id;
  end if;
  if v_id is null and to_regclass('public.night_cast') is not null then
    execute 'select ''night_cast'', c.id, c.store_id, c.name from public.night_cast c
              where c.line_user_id = $1 and c.is_active limit 1'
      into v_kind, v_id, v_store, v_name using p_line_user_id;
  end if;
  if v_id is null and to_regclass('public.salon_staff') is not null then
    execute 'select ''salon_staff'', x.id, x.store_id, x.name from public.salon_staff x
              where x.line_user_id = $1 and x.is_active limit 1'
      into v_kind, v_id, v_store, v_name using p_line_user_id;
  end if;
  if v_id is null and to_regclass('public.pet_staff') is not null then
    execute 'select ''pet_staff'', x.id, x.store_id, x.name from public.pet_staff x
              where x.line_user_id = $1 and x.is_active limit 1'
      into v_kind, v_id, v_store, v_name using p_line_user_id;
  end if;

  if v_id is null then
    return jsonb_build_object('ok', false, 'reply',
      'はじめまして。お店の名簿とつながっていないようです。' || E'\n' ||
      'お手数ですが、お店にこのメッセージをお見せください。');
  end if;

  -- いま受付中の募集をさがします
  select * into p from public.shift_period
   where store_id = v_store and status = 'open'
   order by period_from limit 1;

  if p.id is null then
    return jsonb_build_object('ok', false, 'reply',
      v_name || ' さん' || E'\n' ||
      'いま受付中のシフト募集がありません。お店にご確認ください。');
  end if;

  w := app.wish_get_or_make(p.id, v_kind, v_id, 'line');
  if w.status = 'approved' then
    return jsonb_build_object('ok', false, 'reply',
      v_name || ' さん' || E'\n' ||
      'この期間はもう確定しています。変更はお店にご連絡ください。');
  end if;

  v_lines := regexp_split_to_array(coalesce(p_text, ''), E'[\n\r、,]+');

  foreach v_line in array v_lines loop
    v_line := btrim(v_line);
    continue when v_line = '';

    -- 日づけ： 10/1・10月1日・1日 のどれでも
    v_md := regexp_match(v_line, '(\d{1,2})\s*[/月]\s*(\d{1,2})');
    if v_md is null then
      v_md := regexp_match(v_line, '^(\d{1,2})\s*日');
      if v_md is not null then
        v_md := array[to_char(p.period_from, 'MM'), v_md[1]];
      end if;
    end if;
    if v_md is null then
      bad := bad || case when bad = '' then '' else E'\n' end || v_line;
      continue;
    end if;

    -- 年は、期間からあてます（12月→1月をまたぐ場合も拾えます）
    v_y := extract(year from p.period_from)::integer;
    begin
      v_date := make_date(v_y, v_md[1]::integer, v_md[2]::integer);
    exception when others then
      bad := bad || case when bad = '' then '' else E'\n' end || v_line;
      continue;
    end;
    if v_date < p.period_from then
      v_date := v_date + interval '1 year';
    end if;
    if v_date < p.period_from or v_date > p.period_to then
      bad := bad || case when bad = '' then '' else E'\n' end ||
             v_line || '（この期間の外です）';
      continue;
    end if;

    -- 休みかどうか
    if v_line ~ '(休|やすみ|ヤスミ|NG|ng|×|✕|✖)' then
      v_wkind := 'ng'; v_from := null; v_to := null;
    else
      v_wkind := 'ok';
      -- 時刻： 10-17・10:00-17:00・10時〜17時
      v_hm := regexp_match(v_line,
              '(\d{1,2})\s*[:：時]?\s*(\d{2})?\s*[-−〜~ー–]\s*(\d{1,2})\s*[:：時]?\s*(\d{2})?');
      if v_hm is null then
        v_from := null; v_to := null;
      else
        begin
          v_from := make_time(v_hm[1]::integer, coalesce(v_hm[2], '0')::integer, 0);
          v_to   := make_time(least(v_hm[3]::integer, 23), coalesce(v_hm[4], '0')::integer, 0);
        exception when others then
          v_from := null; v_to := null;
        end;
      end if;
    end if;

    insert into public.shift_wish_day(
      wish_id, business_date, kind, from_time, to_time, note)
    values (w.id, v_date, v_wkind, v_from, v_to, 'LINEから')
    on conflict (wish_id, business_date) do update
      set kind = excluded.kind, from_time = excluded.from_time,
          to_time = excluded.to_time, note = excluded.note;
    n := n + 1;
  end loop;

  if n = 0 then
    return jsonb_build_object('ok', false, 'reply',
      v_name || ' さん' || E'\n' ||
      '日にちが読み取れませんでした。' || E'\n\n' ||
      'こんなふうに送ってください：' || E'\n' ||
      '10/1 10-17' || E'\n' || '10/2 休' || E'\n' || '10/3 17:00-23:30');
  end if;

  update public.shift_wish
     set status = 'submitted', submitted_at = now(), source = 'line', updated_at = now()
   where id = w.id;

  return jsonb_build_object('ok', true, 'count', n, 'wish_id', w.id,
    'reply',
      v_name || ' さん' || E'\n' ||
      n || '日ぶん、うけとりました。' || E'\n' ||
      (select string_agg(to_char(d.business_date, 'FMMM/FMDD') || ' ' ||
                case d.kind when 'ng' then '休み'
                     else coalesce(to_char(d.from_time, 'HH24:MI'), '時間おまかせ') ||
                          case when d.to_time is null then ''
                               else '〜' || to_char(d.to_time, 'HH24:MI') end end,
                E'\n' order by d.business_date)
         from public.shift_wish_day d where d.wish_id = w.id) ||
      case when bad = '' then ''
           else E'\n\n' || '※つぎの行は読み取れませんでした：' || E'\n' || bad end ||
      E'\n\n' || '確定したら、またお知らせします。');
end;
$$;

revoke all on function public.wish_from_line(text, text) from anon, authenticated;


-- ----------------------------------------------------------------------------
--  だれのLINEかを、結びつけます
--
--   スタッフが、お店のLINE公式アカウントを友だち追加すると、
--   ここに「まだ名前とつながっていないLINE」がたまります。
--   お店の画面で、名簿のだれかを選んで結びつけます。
--   （LINEのIDを手で写す必要がなくなります）
-- ----------------------------------------------------------------------------
create table if not exists public.line_link (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  line_user_id  text not null,
  display_name  text,
  picture_url   text,
  subject_kind  text,
  subject_id    uuid,
  linked_by     uuid references public.staff(id) on delete set null,
  linked_at     timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  unique (tenant_id, line_user_id)
);
create index if not exists idx_line_link on public.line_link(tenant_id, subject_id);

-- 友だち追加や発言があったときに呼びます（Edge Function から）
create or replace function public.line_seen(
  p_tenant uuid, p_line_user_id text, p_name text default null, p_pic text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare r public.line_link;
begin
  insert into public.line_link(tenant_id, line_user_id, display_name, picture_url)
  values (p_tenant, p_line_user_id, p_name, p_pic)
  on conflict (tenant_id, line_user_id) do update
    set display_name = coalesce(excluded.display_name, public.line_link.display_name),
        picture_url  = coalesce(excluded.picture_url,  public.line_link.picture_url),
        last_seen_at = now()
  returning * into r;

  return jsonb_build_object(
    'linked', (r.subject_id is not null),
    'name', coalesce(app.subject_name(r.subject_kind, r.subject_id), r.display_name));
end;
$$;

revoke all on function public.line_seen(uuid, text, text, text) from anon, authenticated;

-- まだ名前とつながっていないLINE
create or replace function public.line_pending(p_store uuid)
returns table (
  id uuid, line_user_id text, display_name text, picture_url text,
  first_seen_at timestamptz, last_seen_at timestamptz
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  if app.my_role() not in ('owner','manager') then
    raise exception 'この画面は、店長以上の権限が必要です';
  end if;

  return query
  select l.id,
         left(l.line_user_id, 6) || '…' || right(l.line_user_id, 4),
         l.display_name, l.picture_url, l.first_seen_at, l.last_seen_at
    from public.line_link l
   where l.tenant_id = app.my_tenant() and l.subject_id is null
   order by l.last_seen_at desc;
end;
$$;

-- 名簿のだれかと結びつけます（名簿の側にも、LINEのIDを書きこみます）
create or replace function public.line_link_set(
  p_id uuid, p_kind text, p_subject uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; l public.line_link; v_tbl text; v_name text;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '結びつけるのは、店長以上の権限が必要です';
  end if;
  select * into l from public.line_link where id = p_id;
  if not found then raise exception 'そのLINEはありません'; end if;
  if l.tenant_id <> app.my_tenant() then
    raise exception 'この法人のものではありません';
  end if;

  v_tbl := app.subject_table(p_kind);
  if v_tbl is null or to_regclass(v_tbl) is null then
    raise exception 'その名簿はありません';
  end if;

  execute format('update %s set line_user_id = $1 where id = $2 returning name', v_tbl)
    into v_name using l.line_user_id, p_subject;
  if v_name is null then raise exception 'その方は見つかりません'; end if;

  update public.line_link
     set subject_kind = p_kind, subject_id = p_subject,
         linked_by = me.id, linked_at = now()
   where id = p_id;

  return jsonb_build_object('ok', true, 'name', v_name,
    'message', v_name || ' さんのLINEとして登録しました');
end;
$$;

-- 結びつきをはずす
create or replace function public.line_link_clear(p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; l public.line_link; v_tbl text;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception 'はずすのは、店長以上の権限が必要です';
  end if;
  select * into l from public.line_link where id = p_id;
  if not found then return false; end if;
  if l.tenant_id <> app.my_tenant() then
    raise exception 'この法人のものではありません';
  end if;

  v_tbl := app.subject_table(l.subject_kind);
  if v_tbl is not null and to_regclass(v_tbl) is not null and l.subject_id is not null then
    execute format('update %s set line_user_id = null where id = $1', v_tbl)
      using l.subject_id;
  end if;

  update public.line_link
     set subject_kind = null, subject_id = null, linked_by = null, linked_at = null
   where id = p_id;
  return true;
end;
$$;


-- ============================================================================
--  9. 見せてよい範囲のきまり（RLS）
-- ============================================================================
alter table public.line_link      enable row level security;
alter table public.shift_slot     enable row level security;
alter table public.shift_period   enable row level security;
alter table public.shift_wish     enable row level security;
alter table public.shift_plan     enable row level security;
alter table public.shift_wish_day enable row level security;

do $$
declare t text;
begin
  foreach t in array array['shift_slot','shift_period','shift_wish','shift_plan'] loop
    execute format('drop policy if exists p_%s on public.%I', t, t);
    execute format(
      'create policy p_%s on public.%I for all to authenticated
         using (app.can_store(store_id)) with check (app.can_store(store_id))', t, t);
  end loop;
end $$;

drop policy if exists p_line_link on public.line_link;
create policy p_line_link on public.line_link for all to authenticated
  using (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'))
  with check (tenant_id = app.my_tenant() and app.my_role() in ('owner','manager'));

drop policy if exists p_shift_wish_day on public.shift_wish_day;
create policy p_shift_wish_day on public.shift_wish_day for all to authenticated
  using (exists (select 1 from public.shift_wish w
                  where w.id = wish_id and app.can_store(w.store_id)))
  with check (exists (select 1 from public.shift_wish w
                  where w.id = wish_id and app.can_store(w.store_id)));


-- ============================================================================
--  10. 画面から呼べるようにします
--
--     本人のページ（ログインなし）から呼べるのは、次の4つだけです。
--     どれも「合いことば」がないと、何も返しません。
-- ============================================================================
grant execute on function
  public.wish_open(text),
  public.wish_set(text, jsonb, text),
  public.wish_submit(text, text),
  public.wish_fixed(text)
to anon, authenticated;

grant select, insert, update, delete on
  public.shift_slot, public.shift_period, public.shift_wish,
  public.shift_wish_day, public.shift_plan
to authenticated;

grant execute on function
  public.shift_slot_seed(uuid),
  public.shift_slot_save(uuid, uuid, text, time, time, text, integer, boolean),
  public.shift_period_open(uuid, date, text, timestamptz),
  public.shift_period_status(uuid, text),
  public.shift_period_list(uuid, integer),
  public.shift_people(uuid),
  public.wish_link(uuid, text, uuid, text),
  public.wish_link_all(uuid, text),
  public.wish_board(uuid),
  public.wish_detail(uuid),
  public.wish_set_by_staff(uuid, text, uuid, jsonb, text),
  public.wish_approve(uuid, text),
  public.wish_return(uuid, text),
  public.wish_send(uuid, text, text),
  public.wish_remind(uuid, text),
  public.wish_day_count(uuid),
  public.line_pending(uuid),
  public.line_link_set(uuid, text, uuid),
  public.line_link_clear(uuid)
to authenticated;

grant select, insert, update, delete on public.line_link to authenticated;


-- ============================================================================
--  確認用
--   select * from public.shift_period_open('店舗ID');
--   select * from public.wish_board('募集ID');
--   select * from public.wish_day_count('募集ID');
-- ============================================================================


-- ############################################################################
-- #
-- #   2. 届出・許可証 ＋ 給与明細の送り先   （018_documents.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通  018_documents.sql
--
--  届出書類・許可証の控えと、更新期限
--
--   ・営業許可証、食品衛生責任者証、防火管理者、保険証券、賃貸借契約……
--     「控えをとっておきたいもの」と「期限が来るもの」をまとめます
--   ・証明書そのものを、写真やPDFで取りこんで残せます
--   ・期限が近づくと、お店の画面でお知らせします
--   ・書類ごとに「みんなに見せる／店長以上だけ」を選べます
--
--  ＜だいじなこと＞
--   ・許可証には、代表者名や住所が入っていることがあります。
--     はじめは「店長以上だけ」にしてあります。
--     店内掲示が要るものだけ「みんなに見せる」に変えてください。
--   ・ひな形は「よくあるもの」です。必要な届出は、業種・地域・規模で変わります。
--     実際の要否は、行政書士さんや所管の窓口にご確認ください。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 書類
-- ============================================================================
create table if not exists public.store_doc (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenant(id) on delete cascade,
  store_id        uuid not null references public.store(id) on delete cascade,
  category        text not null default 'license',
    -- license（許可・免許）/ notify（届出）/ insurance（保険）/ contract（契約）
    -- / inspection（点検・検査）/ other（そのほか）
  name            text not null,              -- 「飲食店営業許可証」
  doc_no          text,                       -- 許可番号・証券番号
  holder          text,                       -- 名義（お店・代表者・担当者）
  issuer          text,                       -- 出しているところ（保健所・消防署など）
  issued_on       date,                       -- 交付日
  expires_on      date,                       -- 期限（ないものは空のまま）
  renew_lead_days integer not null default 60,-- 何日前からお知らせするか
  visibility      text not null default 'boss', -- boss（店長以上だけ）/ staff（みんな）
  must_post       boolean not null default false, -- 店内に掲示が要るもの
  note            text,
  sort_no         integer not null default 100,
  is_active       boolean not null default true,
  created_by      uuid references public.staff(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (store_id, name)
);
create index if not exists idx_store_doc on public.store_doc(store_id, is_active, expires_on);

drop trigger if exists trg_store_doc_touch on public.store_doc;
create trigger trg_store_doc_touch before update on public.store_doc
for each row execute function app.touch_updated_at();


-- 取りこんだ写真・PDF
create table if not exists public.store_doc_file (
  id          uuid primary key default gen_random_uuid(),
  doc_id      uuid not null references public.store_doc(id) on delete cascade,
  path        text not null,                  -- 置き場所（imports と同じしくみ）
  file_name   text,
  mime        text,
  bytes       integer,
  page        integer not null default 1,
  note        text,
  uploaded_by uuid references public.staff(id) on delete set null,
  uploaded_at timestamptz not null default now()
);
create index if not exists idx_store_doc_file on public.store_doc_file(doc_id, page);


-- 置き場所（Supabase の Storage）。なければ作ります。
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public)
    values ('docs', 'docs', false)
    on conflict (id) do nothing;
  end if;
end $$;


-- ============================================================================
--  2. ひな形
--
--    業種にあわせて、よくある書類をならべます。
--    中身は空です（期限と番号は、お店ごとに入れてください）。
-- ============================================================================
create or replace function app.store_doc_seed_core(p_store uuid, p_industry text default null)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; v_ind text; n integer;
begin
  select * into st from public.store where id = p_store;
  v_ind := coalesce(nullif(p_industry, ''), st.industry, 'food');

  -- どの業種にもあるもの
  insert into public.store_doc(
    tenant_id, store_id, category, name, issuer, renew_lead_days,
    visibility, must_post, note, sort_no)
  select st.tenant_id, p_store, v.cat, v.name, v.issuer, v.lead,
         v.vis, v.post, v.note, v.sort
    from (values
      ('contract',   '賃貸借契約書',       '貸主', 90, 'boss',  false,
       '更新の時期が近づいたら、条件の見直しも一緒に', 10),
      ('insurance',  '火災保険',           '保険会社', 60, 'boss',  false,
       '証券番号と、連絡先の控え', 20),
      ('insurance',  '賠償責任保険',       '保険会社', 60, 'boss',  false,
       'お客様への賠償にそなえるもの', 30),
      ('inspection', '消防設備点検の報告', '消防署', 60, 'boss',  false,
       '年に1〜2回。報告の控えを残しておきます', 40),
      ('other',      '従業員名簿',         '自社', 0, 'boss',  false,
       '備え付けが要るもの。このツールの名簿がそのまま使えます', 900)
    ) as v(cat, name, issuer, lead, vis, post, note, sort)
   where not exists (select 1 from public.store_doc x
                      where x.store_id = p_store and x.name = v.name);

  if v_ind = 'food' then
    insert into public.store_doc(
      tenant_id, store_id, category, name, issuer, renew_lead_days,
      visibility, must_post, note, sort_no)
    select st.tenant_id, p_store, v.cat, v.name, v.issuer, v.lead,
           v.vis, v.post, v.note, v.sort
      from (values
        ('license', '飲食店営業許可証',       '保健所', 90, 'staff', true,
         '期限あり。更新は期限の前に。店内に掲示します', 110),
        ('license', '食品衛生責任者の資格',   '食品衛生協会', 60, 'staff', true,
         'お店に1人は必要です。掲示します', 120),
        ('notify',  '防火管理者の選任届',     '消防署', 0, 'boss', false,
         '収容人数によって要ります。人が代わったら出し直します', 130),
        ('notify',  '深夜酒類提供飲食店営業開始届出書', '警察署', 0, 'boss', false,
         '深夜0時をまわってお酒を出すお店。出していない場合は要確認', 140),
        ('inspection', 'グリストラップ清掃の記録', '清掃業者', 30, 'boss', false,
         '定期の清掃記録', 150)
      ) as v(cat, name, issuer, lead, vis, post, note, sort)
     where not exists (select 1 from public.store_doc x
                        where x.store_id = p_store and x.name = v.name);

  elsif v_ind in ('night','cast') then
    insert into public.store_doc(
      tenant_id, store_id, category, name, issuer, renew_lead_days,
      visibility, must_post, note, sort_no)
    select st.tenant_id, p_store, v.cat, v.name, v.issuer, v.lead,
           v.vis, v.post, v.note, v.sort
      from (values
        ('license', '風俗営業等の許可証',     '公安委員会', 90, 'boss', true,
         '種別によって中身が変わります。行政書士さんにご確認ください', 110),
        ('notify',  '深夜酒類提供飲食店営業開始届出書', '警察署', 0, 'boss', false,
         '深夜にお酒を出すお店', 120),
        ('license', '飲食店営業許可証',       '保健所', 90, 'staff', true,
         '期限あり。更新は期限の前に', 130),
        ('notify',  '管理者の選任',           '公安委員会', 0, 'boss', false,
         '人が代わったら届け出ます', 140),
        ('other',   '在籍者の年齢確認の記録', '自社', 0, 'boss', false,
         'いつ・だれが・何の書類で確認したかの記録。'
         '身分証の画像そのものは残さない運用にしています', 150)
      ) as v(cat, name, issuer, lead, vis, post, note, sort)
     where not exists (select 1 from public.store_doc x
                        where x.store_id = p_store and x.name = v.name);

  elsif v_ind = 'salon' then
    insert into public.store_doc(
      tenant_id, store_id, category, name, issuer, renew_lead_days,
      visibility, must_post, note, sort_no)
    select st.tenant_id, p_store, v.cat, v.name, v.issuer, v.lead,
           v.vis, v.post, v.note, v.sort
      from (values
        ('notify',  '美容所（理容所）開設届',   '保健所', 0, 'staff', true, '', 110),
        ('license', '管理美容師（管理理容師）', '保健所', 0, 'staff', true,
         '従業者が2人以上のお店で要ります', 120),
        ('license', '美容師・理容師の免許',     '厚生労働省', 0, 'boss', false,
         '在籍している方のぶん', 130),
        ('inspection', '器具の消毒記録',        '自社', 0, 'staff', false, '', 140)
      ) as v(cat, name, issuer, lead, vis, post, note, sort)
     where not exists (select 1 from public.store_doc x
                        where x.store_id = p_store and x.name = v.name);

  elsif v_ind = 'pet' then
    insert into public.store_doc(
      tenant_id, store_id, category, name, issuer, renew_lead_days,
      visibility, must_post, note, sort_no)
    select st.tenant_id, p_store, v.cat, v.name, v.issuer, v.lead,
           v.vis, v.post, v.note, v.sort
      from (values
        ('license', '第一種動物取扱業の登録証', '都道府県', 120, 'staff', true,
         '5年ごとの更新。期限を切らさないよう、早めに', 110),
        ('license', '動物取扱責任者の資格',     '都道府県', 60, 'staff', true,
         '研修の受講記録もあわせて', 120),
        ('other',   '標識（登録内容の掲示）',   '自社', 0, 'staff', true,
         '見やすいところに掲示します', 130),
        ('other',   '台帳（顧客・動物の記録）', '自社', 0, 'boss', false,
         '備え付けが要るもの', 140)
      ) as v(cat, name, issuer, lead, vis, post, note, sort)
     where not exists (select 1 from public.store_doc x
                        where x.store_id = p_store and x.name = v.name);
  end if;

  select count(*)::integer into n from public.store_doc
   where store_id = p_store and is_active;
  return n;
end;
$$;

create or replace function public.store_doc_seed(p_store uuid, p_industry text default null)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '書類の設定は、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  return app.store_doc_seed_core(p_store, p_industry);
end;
$$;

revoke all on function app.store_doc_seed_core(uuid, text) from anon, authenticated;


-- ============================================================================
--  3. 出し入れ
-- ============================================================================
create or replace function public.store_doc_save(
  p_store uuid, p_id uuid default null,
  p_name text default null, p_category text default null,
  p_no text default null, p_holder text default null, p_issuer text default null,
  p_issued date default null, p_expires date default null,
  p_lead integer default null, p_visibility text default null,
  p_must_post boolean default null, p_note text default null,
  p_sort integer default null, p_active boolean default null)
returns public.store_doc
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; r public.store_doc;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '書類を直すには、店長以上の権限が必要です';
  end if;
  if not app.can_store(p_store) then raise exception 'この店舗を操作する権限がありません'; end if;
  select * into st from public.store where id = p_store;

  if p_visibility is not null and p_visibility not in ('boss','staff') then
    raise exception '見せる範囲は、店長以上だけ・みんな のどちらかです';
  end if;
  if p_category is not null and p_category not in
     ('license','notify','insurance','contract','inspection','other') then
    raise exception 'その種類は選べません';
  end if;
  if p_issued is not null and p_expires is not null and p_expires < p_issued then
    raise exception '期限は、交付日よりあとにしてください';
  end if;

  if p_id is null then
    if nullif(btrim(coalesce(p_name, '')), '') is null then
      raise exception '書類の名前を入れてください';
    end if;
    insert into public.store_doc(
      tenant_id, store_id, category, name, doc_no, holder, issuer,
      issued_on, expires_on, renew_lead_days, visibility, must_post,
      note, sort_no, created_by)
    values (st.tenant_id, p_store, coalesce(p_category, 'license'), btrim(p_name),
            p_no, p_holder, p_issuer, p_issued, p_expires,
            coalesce(p_lead, 60), coalesce(p_visibility, 'boss'),
            coalesce(p_must_post, false), p_note, coalesce(p_sort, 100), me.id)
    returning * into r;
  else
    update public.store_doc
       set category        = coalesce(p_category, category),
           name            = coalesce(nullif(btrim(coalesce(p_name,'')),''), name),
           doc_no          = coalesce(p_no, doc_no),
           holder          = coalesce(p_holder, holder),
           issuer          = coalesce(p_issuer, issuer),
           issued_on       = coalesce(p_issued, issued_on),
           expires_on      = coalesce(p_expires, expires_on),
           renew_lead_days = coalesce(p_lead, renew_lead_days),
           visibility      = coalesce(p_visibility, visibility),
           must_post       = coalesce(p_must_post, must_post),
           note            = coalesce(p_note, note),
           sort_no         = coalesce(p_sort, sort_no),
           is_active       = coalesce(p_active, is_active)
     where id = p_id and store_id = p_store
     returning * into r;
    if not found then raise exception 'その書類はありません'; end if;
  end if;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (st.tenant_id, p_store, me.id, 'store_doc_save', 'store_doc', r.id::text,
          jsonb_build_object('name', r.name, 'expires_on', r.expires_on));
  return r;
end;
$$;

-- 期限だけを更新する（更新したとき、いちばんよく使います）
create or replace function public.store_doc_renew(
  p_id uuid, p_issued date, p_expires date, p_no text default null)
returns public.store_doc
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; r public.store_doc;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '書類を直すには、店長以上の権限が必要です';
  end if;
  select * into r from public.store_doc where id = p_id;
  if not found then raise exception 'その書類はありません'; end if;
  if not app.can_store(r.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  update public.store_doc
     set issued_on = coalesce(p_issued, issued_on),
         expires_on = p_expires,
         doc_no = coalesce(p_no, doc_no)
   where id = p_id returning * into r;
  return r;
end;
$$;

create or replace function public.store_doc_list(
  p_store uuid, p_category text default null, p_all boolean default false)
returns table (
  id uuid, category text, category_label text, name text,
  doc_no text, holder text, issuer text,
  issued_on date, expires_on date, days_left integer,
  renew_lead_days integer, visibility text, visibility_label text,
  must_post boolean, files integer, note text, is_active boolean,
  state text, warn text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare v_boss boolean;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  v_boss := app.my_role() in ('owner','manager');

  return query
  select d.id, d.category,
         case d.category
           when 'license' then '許可・免許' when 'notify' then '届出'
           when 'insurance' then '保険' when 'contract' then '契約'
           when 'inspection' then '点検・検査' else 'そのほか' end,
         d.name, d.doc_no, d.holder, d.issuer, d.issued_on, d.expires_on,
         case when d.expires_on is null then null else (d.expires_on - current_date) end,
         d.renew_lead_days, d.visibility,
         case d.visibility when 'staff' then 'みんな' else '店長以上だけ' end,
         d.must_post,
         coalesce((select count(*)::integer from public.store_doc_file f
                    where f.doc_id = d.id), 0),
         d.note, d.is_active,
         case when d.expires_on is null then 'none'
              when d.expires_on < current_date then 'expired'
              when (d.expires_on - current_date) <= d.renew_lead_days then 'soon'
              else 'ok' end,
         nullif(concat_ws(' / ',
           case when d.expires_on is not null and d.expires_on < current_date
                then '期限が ' || (current_date - d.expires_on) || '日すぎています' end,
           case when d.expires_on is not null and d.expires_on >= current_date
                 and (d.expires_on - current_date) <= d.renew_lead_days
                then 'あと ' || (d.expires_on - current_date) || '日で期限です' end,
           case when d.must_post and not exists (
                  select 1 from public.store_doc_file f where f.doc_id = d.id)
                then '掲示が要る書類です。控えの取りこみがまだです' end
         ), '')
    from public.store_doc d
   where d.store_id = p_store
     and (p_all or d.is_active)
     and (p_category is null or d.category = p_category)
     and (v_boss or d.visibility = 'staff')
   order by
     case when d.expires_on is null then 2 else 1 end,
     d.expires_on nulls last, d.sort_no, d.name;
end;
$$;

-- 期限が近い・すぎているものだけ
create or replace function public.store_doc_alerts(p_store uuid)
returns table (
  id uuid, name text, category_label text, expires_on date,
  days_left integer, state text, message text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  return query
  select d.id, d.name, d.category_label, d.expires_on, d.days_left, d.state,
         case d.state
           when 'expired' then d.name || ' の期限が ' ||
                (current_date - d.expires_on) || '日すぎています。すぐに確認してください'
           when 'soon' then d.name || ' は、あと ' || d.days_left ||
                '日で期限です（' || to_char(d.expires_on, 'FMMM月FMDD日') || '）'
           else d.name end
    from public.store_doc_list(p_store, null, false) d
   where d.state in ('expired','soon')
   order by d.expires_on;
end;
$$;

-- 全店ぶんの期限（本部で見ます）
create or replace function public.store_doc_alerts_all()
returns table (
  store_id uuid, store_name text, id uuid, name text,
  expires_on date, days_left integer, state text, message text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare v_t uuid; r record;
begin
  v_t := app.my_tenant();
  if v_t is null then raise exception 'ログインが必要です'; end if;
  if app.my_role() not in ('owner','manager') then
    raise exception '全店の画面は、店長以上の権限が必要です';
  end if;

  for r in select s.id, s.name from public.store s
            where s.tenant_id = v_t and s.is_active order by s.name loop
    return query
      select r.id, r.name, a.id, a.name, a.expires_on, a.days_left, a.state, a.message
        from public.store_doc_alerts(r.id) a;
  end loop;
end;
$$;


-- ============================================================================
--  4. 写真・PDFの取りこみ
--
--    画面から Storage に上げてから、その置き場所をここに書きとめます。
-- ============================================================================
create or replace function public.store_doc_file_add(
  p_doc uuid, p_path text, p_file_name text default null,
  p_mime text default null, p_bytes integer default null,
  p_page integer default 1, p_note text default null)
returns public.store_doc_file
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; d public.store_doc; r public.store_doc_file;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '書類の取りこみは、店長以上の権限が必要です';
  end if;
  select * into d from public.store_doc where id = p_doc;
  if not found then raise exception 'その書類はありません'; end if;
  if not app.can_store(d.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if nullif(btrim(coalesce(p_path, '')), '') is null then
    raise exception 'ファイルの置き場所がわかりません';
  end if;

  insert into public.store_doc_file(
    doc_id, path, file_name, mime, bytes, page, note, uploaded_by)
  values (p_doc, btrim(p_path), p_file_name, p_mime, p_bytes,
          greatest(coalesce(p_page, 1), 1), p_note, me.id)
  returning * into r;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (d.tenant_id, d.store_id, me.id, 'store_doc_file_add', 'store_doc', d.id::text,
          jsonb_build_object('name', d.name, 'file', p_file_name));
  return r;
end;
$$;

create or replace function public.store_doc_files(p_doc uuid)
returns table (
  id uuid, path text, file_name text, mime text, bytes integer,
  page integer, note text, uploaded_at timestamptz, uploaded_name text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare d public.store_doc; v_boss boolean;
begin
  select * into d from public.store_doc where id = p_doc;
  if not found then raise exception 'その書類はありません'; end if;
  if not app.can_store(d.store_id) then raise exception 'この書類を見る権限がありません'; end if;
  v_boss := app.my_role() in ('owner','manager');
  if d.visibility = 'boss' and not v_boss then
    raise exception 'この書類は、店長以上の方だけがご覧になれます';
  end if;

  return query
  select f.id, f.path, f.file_name, f.mime, f.bytes, f.page, f.note,
         f.uploaded_at, s.name
    from public.store_doc_file f
    left join public.staff s on s.id = f.uploaded_by
   where f.doc_id = p_doc
   order by f.page, f.uploaded_at;
end;
$$;

create or replace function public.store_doc_file_remove(p_id uuid)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; f public.store_doc_file; d public.store_doc;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '書類の取りこみを消すには、店長以上の権限が必要です';
  end if;
  select * into f from public.store_doc_file where id = p_id;
  if not found then return false; end if;
  select * into d from public.store_doc where id = f.doc_id;
  if not app.can_store(d.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  delete from public.store_doc_file where id = p_id;
  return true;
end;
$$;


-- ============================================================================
--  5. 見せてよい範囲のきまり（RLS）
--
--    「店長以上だけ」の書類は、スタッフの画面には1行も返りません。
-- ============================================================================
alter table public.store_doc      enable row level security;
alter table public.store_doc_file enable row level security;

drop policy if exists p_store_doc on public.store_doc;
create policy p_store_doc on public.store_doc for all to authenticated
  using (app.can_store(store_id)
         and (visibility = 'staff' or app.my_role() in ('owner','manager')))
  with check (app.can_store(store_id) and app.my_role() in ('owner','manager'));

drop policy if exists p_store_doc_file on public.store_doc_file;
create policy p_store_doc_file on public.store_doc_file for all to authenticated
  using (exists (select 1 from public.store_doc d
                  where d.id = doc_id and app.can_store(d.store_id)
                    and (d.visibility = 'staff' or app.my_role() in ('owner','manager'))))
  with check (exists (select 1 from public.store_doc d
                  where d.id = doc_id and app.can_store(d.store_id)
                    and app.my_role() in ('owner','manager')));

-- Storage のほうにも、同じきまりを入れます（Supabase のときだけ）
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    execute $q$ drop policy if exists p_docs_read on storage.objects $q$;
    execute $q$
      create policy p_docs_read on storage.objects for select to authenticated
        using (bucket_id = 'docs'
               and app.my_tenant() is not null
               and (storage.foldername(name))[1] = app.my_tenant()::text) $q$;

    execute $q$ drop policy if exists p_docs_write on storage.objects $q$;
    execute $q$
      create policy p_docs_write on storage.objects for insert to authenticated
        with check (bucket_id = 'docs'
               and app.my_role() in ('owner','manager')
               and (storage.foldername(name))[1] = app.my_tenant()::text) $q$;

    execute $q$ drop policy if exists p_docs_del on storage.objects $q$;
    execute $q$
      create policy p_docs_del on storage.objects for delete to authenticated
        using (bucket_id = 'docs'
               and app.my_role() in ('owner','manager')
               and (storage.foldername(name))[1] = app.my_tenant()::text) $q$;
  end if;
end $$;


-- ============================================================================
--  6. 画面から呼べるようにします
-- ============================================================================
grant select, insert, update, delete on
  public.store_doc, public.store_doc_file
to authenticated;

grant execute on function
  public.store_doc_seed(uuid, text),
  public.store_doc_save(uuid, uuid, text, text, text, text, text, date, date,
                        integer, text, boolean, text, integer, boolean),
  public.store_doc_renew(uuid, date, date, text),
  public.store_doc_list(uuid, text, boolean),
  public.store_doc_alerts(uuid),
  public.store_doc_alerts_all(),
  public.store_doc_file_add(uuid, text, text, text, integer, integer, text),
  public.store_doc_files(uuid),
  public.store_doc_file_remove(uuid)
to authenticated;


-- ============================================================================
--  確認用
--   select public.store_doc_seed('店舗ID');
--   select * from public.store_doc_list('店舗ID');
--   select * from public.store_doc_alerts('店舗ID');
-- ============================================================================


-- ============================================================================
--  給与明細の一覧・送信・内訳（業種をまたぐ共通のしくみ）
--
--    どの業種のパックを入れていても、これがあれば給与明細の画面が動きます。
--    名簿の表は app.subject_table（017）から引きます。
-- ============================================================================

create or replace function app.payslip_contact(p_kind text, p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare v_tbl text; v_want text; v_line text; v_mail text;
begin
  -- 業種が増えても、app.subject_table に1行足すだけで効きます
  if to_regprocedure('app.subject_table(text)') is not null then
    execute 'select app.subject_table($1)' into v_tbl using p_kind;
  else
    v_tbl := case p_kind
               when 'night_cast'  then 'public.night_cast'
               when 'cast_member' then 'public.cast_member'
               when 'food_staff'  then 'public.food_staff'
               else null end;
  end if;
  if v_tbl is null or to_regclass(v_tbl) is null then
    return jsonb_build_object('want', 'print', 'line', null, 'mail', null);
  end if;

  execute format(
    'select c.payslip_method, c.line_user_id, c.email from %s c where c.id = $1', v_tbl)
    into v_want, v_line, v_mail using p_id;

  return jsonb_build_object(
    'want', coalesce(v_want, 'print'),
    'line', nullif(v_line, ''),
    'mail', nullif(v_mail, ''));
end;
$$;

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
         c.j->>'want',
         case c.j->>'want'
           when 'line'  then c.j->>'line'
           when 'email' then c.j->>'mail'
           else null end
    from public.payslip p
    cross join lateral (select app.payslip_contact(p.subject_kind, p.subject_id) as j) c
   where p.store_id = p_store
     and (p_ym is null or p.period_ym = p_ym)
     and (p_kind is null or p.subject_kind = p_kind)
   order by p.period_ym desc, p.issue_no;
end;
$$;

create or replace function public.payslip_send(
  p_id uuid, p_method text default null, p_attach_path text default null
) returns public.payslip
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; p public.payslip; st public.store; c jsonb;
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
  c := app.payslip_contact(p.subject_kind, p.subject_id);

  v_method := coalesce(nullif(p_method, ''), c->>'want', 'print');

  if v_method = 'none' then
    raise exception 'この方には「渡さない」の設定になっています';
  end if;
  if v_method not in ('print','line','email') then
    raise exception 'その送り方は選べません';
  end if;

  if v_method in ('line','email') then
    v_to := case v_method when 'line' then c->>'line' else c->>'mail' end;
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

-- 内訳：入っているパックのぶんだけ返します
create or replace function public.payslip_detail(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare p public.payslip; v_daily jsonb; v_sum jsonb; v_items jsonb;
begin
  select * into p from public.payslip where id = p_id;
  if not found then raise exception '明細が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この明細を見る権限がありません'; end if;

  if p.subject_kind = 'night_cast'
     and to_regprocedure('public.night_payroll_daily(uuid,date,date)') is not null then
    execute $q$
      select coalesce((select jsonb_agg(to_jsonb(d) order by d.business_date)
               from public.night_payroll_daily($1, $2, $3) d), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(s))
               from public.night_payroll_item_summary($1, $2, $3) s), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(i) order by i.business_date, i.punched_hm)
               from public.night_payroll_items($1, $2, $3, null) i), '[]'::jsonb)
    $q$ into v_daily, v_sum, v_items using p.subject_id, p.period_from, p.period_to;

  elsif p.subject_kind = 'cast_member'
     and to_regprocedure('public.cast_payroll_daily(uuid,date,date)') is not null then
    execute $q$
      select coalesce((select jsonb_agg(to_jsonb(d) order by d.business_date)
               from public.cast_payroll_daily($1, $2, $3) d), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(s))
               from public.cast_payroll_item_summary($1, $2, $3) s), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(i) order by i.business_date, i.start_hm)
               from public.cast_payroll_items($1, $2, $3, null) i), '[]'::jsonb)
    $q$ into v_daily, v_sum, v_items using p.subject_id, p.period_from, p.period_to;

  elsif p.subject_kind = 'food_staff' then
    select coalesce((select jsonb_agg(to_jsonb(d) order by d.business_date)
             from public.food_labor_daily(p.subject_id, p.period_from, p.period_to) d), '[]'::jsonb),
           coalesce((select jsonb_agg(to_jsonb(s))
             from (select l.label as item_label, l.qty, l.unit, l.amount
                     from public.payslip_line l
                    where l.payslip_id = p.id and l.section = 'earning'
                    order by l.sort_no) s), '[]'::jsonb),
           '[]'::jsonb
      into v_daily, v_sum, v_items;

  else
    raise exception 'この明細の内訳は、まだ用意していません';
  end if;

  return jsonb_build_object(
    'kind', p.subject_kind,
    'payslip_id', p.id, 'subject_name', p.subject_name,
    'period_from', p.period_from, 'period_to', p.period_to,
    'daily', v_daily, 'summary', v_sum, 'items', v_items);
end;
$$;


grant execute on function
  public.payslip_list(uuid, text, text),
  public.payslip_send(uuid, text, text),
  public.payslip_detail(uuid)
to authenticated;


-- ############################################################################
-- #
-- #   3. 権限（だれに何を見せるか）   （019_kengen.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ / 権限パック
--  019_kengen.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜018 を先に実行しておいてください）
--
--  ここでやること
--   1. 「店長以上かどうか」を1か所で決めます（app.is_boss）
--   2. 「ログインしている人が、業種名簿のどの行か」を引けるようにします
--      （app.my_subject）
--   3. 給与明細を、店長以上は全員ぶん・スタッフは自分のぶんだけにします
--   4. 月べつの売上・歩合・人件費・原価・本部の画面を、店長以上だけにします
--
--  だいじなこと
--   ・入っていない業種のぶんは、なにもしません。
--     ナイトだけのお店でも、5業種ぜんぶ入っているお店でも、そのまま流せます。
--   ・何度実行しても壊れません。
--   ・業種のSQL（101〜、201〜、301〜、401〜）を貼り直したあとは、
--     ★このファイルをもう一度流してください。★
--     貼り直すと関数が元に戻り、権限のふたが外れます。
--     このファイルは、外れていたら付け直します。
--
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 店長以上かどうか
-- ============================================================================

create or replace function app.is_boss()
returns boolean
language sql stable security definer set search_path = public, app
as $$
  select coalesce(app.my_role() in ('owner','manager'), false);
$$;


-- ============================================================================
--  2. ログインしている人が、業種名簿のどの行か
--
--   結びつけ方は2とおりです。
--     ・名簿の staff_id に、ログインする人を入れる（おすすめ）
--     ・名簿のメールを、ログインのアドレスと同じにする
--
--   staff_id で結びつけておくと、名簿のメール欄を
--   「明細の届け先」として自由に使えます（Gmailなど）。
--
--   ナイト・キャストの名簿には staff_id がなかったので、ここで足します。
--   これで5業種とも、同じやり方で結びつけられます。
-- ============================================================================

do $$
begin
  if to_regclass('public.night_cast') is not null then
    alter table public.night_cast
      add column if not exists staff_id uuid references public.staff(id) on delete set null;
    comment on column public.night_cast.staff_id
      is 'ログインするスタッフ。明細を「ご自分のぶんだけ」見せるための結びつけ';
  end if;
  if to_regclass('public.cast_member') is not null then
    alter table public.cast_member
      add column if not exists staff_id uuid references public.staff(id) on delete set null;
    comment on column public.cast_member.staff_id
      is 'ログインするスタッフ。明細を「ご自分のぶんだけ」見せるための結びつけ';
  end if;
end $$;

create or replace function app.my_subject()
returns table (subject_kind text, subject_id uuid)
language plpgsql stable security definer set search_path = public, app
as $$
declare
  me     public.staff;
  k      text;
  tbl    text;
  has_sid boolean;
begin
  select * into me from public.staff
   where auth_user_id = auth.uid() and is_active limit 1;
  if me.id is null then return; end if;

  foreach k in array array['food_staff','night_cast','cast_member',
                           'salon_staff','pet_staff'] loop
    tbl := app.subject_table(k);
    if tbl is null or to_regclass(tbl) is null then continue; end if;

    select exists (
      select 1 from pg_attribute a
       where a.attrelid = to_regclass(tbl)
         and a.attname = 'staff_id' and a.attnum > 0 and not a.attisdropped)
      into has_sid;

    if has_sid then
      return query execute format(
        'select %L::text, t.id from %s t
          where t.tenant_id = $1
            and (t.staff_id = $2
                 or (t.email is not null and $3 <> '''' and lower(t.email) = lower($3)))',
        k, tbl) using me.tenant_id, me.id, coalesce(me.email, '');
    else
      return query execute format(
        'select %L::text, t.id from %s t
          where t.tenant_id = $1
            and t.email is not null and $2 <> '''' and lower(t.email) = lower($2)',
        k, tbl) using me.tenant_id, coalesce(me.email, '');
    end if;
  end loop;
end;
$$;

revoke all on function app.is_boss() from anon, authenticated;
revoke all on function app.my_subject() from anon, authenticated;


-- ============================================================================
--  3. ふたを付ける道具
--
--   もとの関数を app スキーマに移して名前を変え、
--   同じ名前・同じ引数の「ふた付き」を public に作り直します。
--   画面から見える名前も使い方も、いっさい変わりません。
-- ============================================================================

--  ふたが付いているかの目印。これが関数の中にあれば、もう付いています。
--    __DANDORI_GUARD__

create or replace function app.add_guard(
  p_sig  text,          -- 例： 'public.salon_month(uuid,text)'
  p_kind text,          -- 'boss'（店長以上だけ）/ 'mine'（店長以上＋本人）
  p_what text           -- エラー文に出す、画面の呼び名
) returns text
language plpgsql
as $$
declare
  o        oid;
  v_name   text;
  v_core   text;
  v_args   text;   -- 引数（名前・型・既定値つき）
  v_ident  text;   -- 引数（名前と型）
  v_types  text;   -- 引数の型だけ
  v_names  text;   -- 引数の名前だけ
  v_ret    text;
  v_vol    text;
  v_first  text;
  v_body   text;
  v_guard  text;
begin
  o := to_regprocedure(p_sig);
  if o is null then
    return 'とばしました（入っていません）: ' || p_sig;
  end if;

  if pg_get_functiondef(o) like '%__DANDORI_GUARD__%' then
    return 'そのまま（もう付いています）: ' || p_sig;
  end if;

  select p.proname,
         pg_get_function_arguments(o),
         pg_get_function_identity_arguments(o),
         pg_get_function_result(o),
         case p.provolatile when 'i' then 'immutable'
                            when 's' then 'stable' else 'volatile' end,
         coalesce(array_to_string(p.proargnames[1:p.pronargs], ', '), ''),
         coalesce(p.proargnames[1], '')
    into v_name, v_args, v_ident, v_ret, v_vol, v_names, v_first
    from pg_proc p where p.oid = o;

  select coalesce(string_agg(format_type(t, null), ',' order by ord), '')
    into v_types
    from pg_proc p, unnest(p.proargtypes) with ordinality as u(t, ord)
   where p.oid = o;

  v_core := v_name || '_nolid';

  -- 前に作った「ふた無し」が残っていれば、いちど消します
  if to_regprocedure('app.' || quote_ident(v_core) || '(' || v_types || ')') is not null then
    execute format('drop function app.%I(%s)', v_core, v_types);
  end if;

  execute format('alter function %s set schema app', p_sig);
  execute format('alter function app.%I(%s) rename to %I', v_name, v_types, v_core);
  execute format('revoke all on function app.%I(%s) from anon, authenticated',
                 v_core, v_types);

  if p_kind = 'mine' then
    if v_first = '' then
      raise exception 'app.add_guard: 引数に名前がありません -> %', p_sig;
    end if;
    v_guard := format(
      $g$  if not (app.is_boss() or exists (
             select 1 from app.my_subject() m where m.subject_id = %s)) then
             raise exception '%s は、ご自分のぶんだけご覧いただけます';
           end if;$g$, v_first, p_what);
  else
    v_guard := format(
      $g$  if not app.is_boss() then
             raise exception '%s は、店長以上の方だけがご覧いただけます';
           end if;$g$, p_what);
  end if;

  if v_ret like 'TABLE(%' or v_ret like 'SETOF %' then
    v_body := format('begin  -- __DANDORI_GUARD__%s%s  return query select * from app.%I(%s);%send;',
                     E'\n', v_guard || E'\n', v_core, v_names, E'\n');
  else
    v_body := format('begin  -- __DANDORI_GUARD__%s%s  return app.%I(%s);%send;',
                     E'\n', v_guard || E'\n', v_core, v_names, E'\n');
  end if;

  execute format(
    'create or replace function %I.%I(%s) returns %s
       language plpgsql %s security definer set search_path = public, app
     as %L',
    'public', v_name, v_args, v_ret, v_vol, v_body);

  execute format('grant execute on function public.%I(%s) to authenticated',
                 v_name, v_types);

  return 'ふたを付けました: ' || p_sig;
end;
$$;

revoke all on function app.add_guard(text, text, text) from anon, authenticated;


-- ============================================================================
--  4. どの画面を、だれに見せるか
-- ============================================================================

do $$
declare r text;
begin
  -- ---------------------------------------------------------- 店長以上だけ
  foreach r in array array[
    -- ナイト
    'public.night_payroll_preview(uuid,date,date)|給与の計算',
    'public.night_payroll_monthly(uuid,integer)|月別の給与',
    'public.night_payroll_confirm(uuid,date,date,uuid)|給与の確定',
    -- キャスト
    'public.cast_payroll_preview(uuid,date,date)|報酬の計算',
    'public.cast_payroll_monthly(uuid,integer)|月別の報酬',
    'public.cast_payroll_confirm(uuid,date,date,uuid)|報酬の確定',
    'public.cast_media_costs(uuid,text)|広告費',
    'public.cast_media_cost_set(uuid,text,integer,text)|広告費',
    'public.cast_hq_monthly(integer)|本部の画面',
    'public.cast_hq_ranking(date,date,integer)|本部の画面',
    'public.cast_hq_today(date)|本部の画面',
    -- フード
    'public.food_month(uuid,text)|月べつの売上',
    'public.food_month_total(uuid,text)|月べつの売上',
    'public.food_month_input(uuid,text)|月のまとめ',
    'public.food_cost_month(uuid,text)|原価',
    'public.food_labor_month(uuid,text)|月の人件費',
    'public.food_labor_total(uuid,text)|月の人件費',
    'public.food_hq_month(text)|本部の画面',
    'public.food_hq_ranking(text,text)|本部の画面',
    'public.food_hq_today(date)|本部の画面',
    -- サロン
    'public.salon_month(uuid,text)|月べつの売上',
    'public.salon_month_total(uuid,text)|月べつの売上',
    'public.salon_month_input(uuid,text)|月のまとめ',
    'public.salon_staff_month(uuid,text)|スタイリスト別・歩合',
    'public.salon_rental_month(uuid,text)|面貸しの精算',
    'public.salon_retail_month(uuid,text)|店販の成績',
    'public.salon_hq_month(text)|本部の画面',
    'public.salon_hq_ranking(text,integer)|本部の画面',
    'public.salon_hq_today(date)|本部の画面',
    'public.salon_hq_alerts()|本部の画面',
    -- ペット
    'public.pet_month(uuid,text)|月べつの売上',
    'public.pet_month_total(uuid,text)|月べつの売上',
    'public.pet_month_input(uuid,text)|月のまとめ',
    'public.pet_staff_month(uuid,text)|トリマー別・歩合'
  ] loop
    raise notice '%', app.add_guard(split_part(r, '|', 1), 'boss', split_part(r, '|', 2));
  end loop;

  -- ------------------------------------------------ 店長以上＋ご本人だけ
  foreach r in array array[
    'public.night_payroll_daily(uuid,date,date)|給与の内訳',
    'public.night_payroll_items(uuid,date,date,text)|給与の内訳',
    'public.night_payroll_item_summary(uuid,date,date)|給与の内訳',
    'public.night_payroll_cast_history(uuid,integer)|給与の履歴',
    'public.cast_payroll_daily(uuid,date,date)|報酬の内訳',
    'public.cast_payroll_items(uuid,date,date,text)|報酬の内訳',
    'public.cast_payroll_item_summary(uuid,date,date)|報酬の内訳',
    'public.cast_payroll_cast_history(uuid,integer)|報酬の履歴',
    'public.food_labor_daily(uuid,date,date)|給与の内訳'
  ] loop
    raise notice '%', app.add_guard(split_part(r, '|', 1), 'mine', split_part(r, '|', 2));
  end loop;
end;
$$;


-- ============================================================================
--  5. 給与明細は「店長以上は全員ぶん・スタッフはご自分のぶんだけ」
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
declare v_boss boolean;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  v_boss := app.is_boss();

  return query
  select p.id, p.issue_no, p.period_ym, p.period_from, p.period_to,
         p.subject_kind, p.subject_id, p.subject_name,
         p.gross, p.deduction, p.advance, p.net,
         p.status, p.method, p.sent_at,
         c.j->>'want',
         case c.j->>'want'
           when 'line'  then c.j->>'line'
           when 'email' then c.j->>'mail'
           else null end
    from public.payslip p
    cross join lateral (select app.payslip_contact(p.subject_kind, p.subject_id) as j) c
   where p.store_id = p_store
     and (p_ym is null or p.period_ym = p_ym)
     and (p_kind is null or p.subject_kind = p_kind)
     and (v_boss or exists (select 1 from app.my_subject() m
                             where m.subject_kind = p.subject_kind
                               and m.subject_id   = p.subject_id))
   order by p.period_ym desc, p.issue_no;
end;
$$;


--  内訳も、ご本人か店長以上だけ
create or replace function public.payslip_detail(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare p public.payslip; v_daily jsonb; v_sum jsonb; v_items jsonb;
begin
  select * into p from public.payslip where id = p_id;
  if not found then raise exception '明細が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この明細を見る権限がありません'; end if;

  if not (app.is_boss() or exists (
            select 1 from app.my_subject() m
             where m.subject_kind = p.subject_kind and m.subject_id = p.subject_id)) then
    raise exception '給与明細は、ご自分のぶんだけご覧いただけます';
  end if;

  if p.subject_kind = 'night_cast'
     and to_regprocedure('public.night_payroll_daily(uuid,date,date)') is not null then
    execute $q$
      select coalesce((select jsonb_agg(to_jsonb(d) order by d.business_date)
               from public.night_payroll_daily($1, $2, $3) d), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(s))
               from public.night_payroll_item_summary($1, $2, $3) s), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(i) order by i.business_date, i.punched_hm)
               from public.night_payroll_items($1, $2, $3, null) i), '[]'::jsonb)
    $q$ into v_daily, v_sum, v_items using p.subject_id, p.period_from, p.period_to;

  elsif p.subject_kind = 'cast_member'
     and to_regprocedure('public.cast_payroll_daily(uuid,date,date)') is not null then
    execute $q$
      select coalesce((select jsonb_agg(to_jsonb(d) order by d.business_date)
               from public.cast_payroll_daily($1, $2, $3) d), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(s))
               from public.cast_payroll_item_summary($1, $2, $3) s), '[]'::jsonb),
             coalesce((select jsonb_agg(to_jsonb(i) order by i.business_date, i.start_hm)
               from public.cast_payroll_items($1, $2, $3, null) i), '[]'::jsonb)
    $q$ into v_daily, v_sum, v_items using p.subject_id, p.period_from, p.period_to;

  elsif p.subject_kind = 'food_staff' then
    select coalesce((select jsonb_agg(to_jsonb(d) order by d.business_date)
             from public.food_labor_daily(p.subject_id, p.period_from, p.period_to) d), '[]'::jsonb),
           coalesce((select jsonb_agg(to_jsonb(s))
             from (select l.label as item_label, l.qty, l.unit, l.amount
                     from public.payslip_line l
                    where l.payslip_id = p.id and l.section = 'earning'
                    order by l.sort_no) s), '[]'::jsonb),
           '[]'::jsonb
      into v_daily, v_sum, v_items;

  else
    raise exception 'この明細の内訳は、まだ用意していません';
  end if;

  return jsonb_build_object(
    'kind', p.subject_kind,
    'payslip_id', p.id, 'subject_name', p.subject_name,
    'period_from', p.period_from, 'period_to', p.period_to,
    'daily', v_daily, 'summary', v_sum, 'items', v_items);
end;
$$;

grant execute on function public.payslip_list(uuid, text, text) to authenticated;
grant execute on function public.payslip_detail(uuid) to authenticated;


-- ============================================================================
--  6. 画面が「わたしは何ができるか」を聞くところ
--     ログインしたあと1回だけ呼んで、タブの出し分けに使います。
-- ============================================================================

create or replace function public.my_permissions()
returns jsonb
language sql stable security definer set search_path = public, app
as $$
  select jsonb_build_object(
    'role',     coalesce(app.my_role(), ''),
    'is_boss',  app.is_boss(),
    'subjects', coalesce((select jsonb_agg(jsonb_build_object(
                            'kind', m.subject_kind, 'id', m.subject_id))
                            from app.my_subject() m), '[]'::jsonb));
$$;

grant execute on function public.my_permissions() to authenticated;


-- ============================================================================
--  7. ふたが、ぜんぶ閉まっているかの確認
--
--     select * from public.kengen_check();
--
--   「ふたなし」が1行でも出たら、業種のSQLを貼り直したあとに
--   このファイル（だんどり共通）を貼り直し忘れています。
--   もう一度貼れば直ります。
-- ============================================================================

create or replace function public.kengen_check()
returns table (画面 text, 関数 text, ようす text)
language plpgsql stable security definer set search_path = public, app
as $$
declare r text; o oid; sig text;
begin
  --  画面から呼ばれたときは、店長以上の方だけにします。
  --  Supabase の SQL Editor には「ログインしている人」がいない（auth.uid() が空）ので、
  --  そのときは通します。出るのは関数の名前とふたのありなしだけで、
  --  お店のデータは1行も出ません。
  if auth.uid() is not null and not app.is_boss() then
    raise exception 'この確認は、店長以上の方だけです';
  end if;
  foreach r in array array[
    'public.night_payroll_preview(uuid,date,date)|給与の計算',
    'public.night_payroll_monthly(uuid,integer)|月別の給与',
    'public.night_payroll_daily(uuid,date,date)|給与の内訳',
    'public.cast_payroll_preview(uuid,date,date)|報酬の計算',
    'public.cast_payroll_monthly(uuid,integer)|月別の報酬',
    'public.cast_media_costs(uuid,text)|広告費',
    'public.cast_hq_monthly(integer)|本部の画面',
    'public.food_month(uuid,text)|月べつの売上',
    'public.food_cost_month(uuid,text)|原価',
    'public.food_labor_month(uuid,text)|月の人件費',
    'public.food_hq_month(text)|本部の画面',
    'public.salon_month(uuid,text)|月べつの売上',
    'public.salon_staff_month(uuid,text)|スタイリスト別・歩合',
    'public.salon_retail_month(uuid,text)|店販の成績',
    'public.salon_hq_month(text)|本部の画面',
    'public.pet_month(uuid,text)|月べつの売上',
    'public.pet_staff_month(uuid,text)|トリマー別・歩合'
  ] loop
    sig := split_part(r, '|', 1);
    o := to_regprocedure(sig);
    if o is null then continue; end if;              -- 入っていない業種はとばします
    画面   := split_part(r, '|', 2);
    関数   := sig;
    ようす := case when pg_get_functiondef(o) like '%__DANDORI_GUARD__%'
                   then 'ふたあり' else '★ふたなし★' end;
    return next;
  end loop;
end;
$$;

--  ログインなしの方（anon）からは、いっさい呼べないようにします。
--  public から revoke しないと、だれでも呼べたままになります。
revoke all on function public.kengen_check() from public;
revoke all on function public.kengen_check() from anon;
grant execute on function public.kengen_check() to authenticated;
grant execute on function public.kengen_check() to service_role;


-- ============================================================================
--  そのほかの確認用
--    select public.my_permissions();   -- いま入っている人の権限
--    select * from app.my_subject();   -- その人が、業種名簿のどの行か
-- ============================================================================


-- ############################################################################
-- #
-- #   4. 画面の見た目（着せ替え）   （020_mitame.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ / 画面の見た目（着せ替え）
--  020_mitame.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜019 を先に実行しておいてください）
--
--  ここで作るもの
--    ・ログインする人ごとの「画面の見た目」の覚え書き
--    ・読み書きのしくみ（自分のぶんだけ）
--
--  だいじなこと
--    ・見た目は<人ごと>です。同じお店でも、人によって違ってかまいません。
--    ・ほかの人の設定は、1行も見えません。書きかえもできません。
--    ・どの端末・どのブラウザで入っても、同じ見た目になります。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 覚え書きの置き場所
-- ============================================================================

create table if not exists public.ui_pref (
  staff_id    uuid primary key references public.staff(id) on delete cascade,

  --  見せ方： standard（標準）/ large（大きな文字）
  --           night（夜の画面）/ contrast（高コントラスト）
  preset      text not null default 'standard',

  --  細かい設定。null は「テーマのまま」という意味です。
  font        text,          -- udp / sans / round / serif / system
  scheme      text,          -- theme（テーマに合わせる）/ light / dark / auto
  text_size   integer,       -- 90 / 100 / 115 / 130
  bg_color    text,          -- #RRGGBB
  ink_color   text,          -- #RRGGBB

  --  背景のかざり： off（なし）/ pop（イラストが舞う）/ cool（お店の情景）
  --                 photo（写真）
  bg_art      text,

  --  写真をえらんだときの、画像の置き場所と出どころ
  bg_image    text,          -- 取りこんだ画像のみち／さがした画像のアドレス
  bg_from     text,          -- upload（取りこみ）/ search（さがした）
  bg_credit   text,          -- さがした画像の出どころ（記録として残します）

  updated_at  timestamptz not null default now()
);

alter table public.ui_pref add column if not exists bg_art    text;
alter table public.ui_pref add column if not exists bg_image  text;
alter table public.ui_pref add column if not exists bg_from   text;
alter table public.ui_pref add column if not exists bg_credit text;

comment on table public.ui_pref is
  '画面の見た目。ログインする人ごとに1行。ほかの人のぶんは見えません。';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_preset_ck') then
    alter table public.ui_pref add constraint ui_pref_preset_ck
      check (preset in ('standard','large','night','contrast'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_scheme_ck') then
    alter table public.ui_pref add constraint ui_pref_scheme_ck
      check (scheme is null or scheme in ('theme','light','dark','auto'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_font_ck') then
    alter table public.ui_pref add constraint ui_pref_font_ck
      check (font is null or font in ('udp','sans','round','serif','system'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_size_ck') then
    alter table public.ui_pref add constraint ui_pref_size_ck
      check (text_size is null or text_size between 80 and 160);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_bg_ck') then
    alter table public.ui_pref add constraint ui_pref_bg_ck
      check (bg_color is null or bg_color ~ '^#[0-9A-Fa-f]{6}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_ink_ck') then
    alter table public.ui_pref add constraint ui_pref_ink_ck
      check (ink_color is null or ink_color ~ '^#[0-9A-Fa-f]{6}$');
  end if;
  --  前の版（photo なし）の決まりごとが残っていたら、入れ替えます
  if exists (select 1 from pg_constraint where conname = 'ui_pref_art_ck'
               and pg_get_constraintdef(oid) not like '%photo%') then
    alter table public.ui_pref drop constraint ui_pref_art_ck;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ui_pref_art_ck') then
    alter table public.ui_pref add constraint ui_pref_art_ck
      check (bg_art is null or bg_art in ('off','pop','cool','photo'));
  end if;
end $$;

drop trigger if exists trg_touch_ui_pref on public.ui_pref;
create trigger trg_touch_ui_pref before update on public.ui_pref
  for each row execute function app.touch_updated_at();


-- ============================================================================
--  2. 自分のぶんだけ、読み書きできるようにします
-- ============================================================================

alter table public.ui_pref enable row level security;

drop policy if exists p_ui_pref on public.ui_pref;
create policy p_ui_pref on public.ui_pref
  for all
  using      (staff_id = (select id from public.staff
                           where auth_user_id = auth.uid() and is_active limit 1))
  with check (staff_id = (select id from public.staff
                           where auth_user_id = auth.uid() and is_active limit 1));

revoke all on public.ui_pref from anon;
grant select, insert, update, delete on public.ui_pref to authenticated;


-- ============================================================================
--  3. 読む
-- ============================================================================

create or replace function public.ui_pref_get()
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare me public.staff; r public.ui_pref;
begin
  select * into me from app.me();
  if me.id is null then
    --  ログインしていないときは、標準の見た目を返します
    return jsonb_build_object('preset', 'standard');
  end if;

  select * into r from public.ui_pref where staff_id = me.id;
  if not found then
    return jsonb_build_object('preset', 'standard');
  end if;

  return jsonb_build_object(
    'preset',    r.preset,
    'font',      r.font,
    'scheme',    r.scheme,
    'text_size', r.text_size,
    'bg_color',  r.bg_color,
    'ink_color', r.ink_color,
    'bg_art',    r.bg_art,
    'bg_image',  r.bg_image,
    'bg_from',   r.bg_from,
    'bg_credit', r.bg_credit);
end;
$$;


-- ============================================================================
--  4. 書く
--
--    渡さなかった項目は、いまの値のままにします。
--    「標準に戻す」ときは、その項目に '' （空の文字）を渡してください。
-- ============================================================================

drop function if exists public.ui_pref_set(text, text, text, integer, text, text);
drop function if exists public.ui_pref_set(text, text, text, integer, text, text, text);

create or replace function public.ui_pref_set(
  p_preset    text    default null,
  p_font      text    default null,
  p_scheme    text    default null,
  p_size      integer default null,
  p_bg        text    default null,
  p_ink       text    default null,
  p_art       text    default null,
  p_image     text    default null,
  p_from      text    default null,
  p_credit    text    default null
) returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  insert into public.ui_pref(staff_id) values (me.id)
    on conflict (staff_id) do nothing;

  update public.ui_pref
     set preset    = coalesce(nullif(btrim(coalesce(p_preset, '')), ''), preset),
         font      = case when p_font   is null then font
                          else nullif(btrim(p_font), '') end,
         scheme    = case when p_scheme is null then scheme
                          else nullif(btrim(p_scheme), '') end,
         text_size = case when p_size   is null then text_size
                          when p_size = 0       then null
                          else p_size end,
         bg_color  = case when p_bg     is null then bg_color
                          else nullif(btrim(p_bg), '') end,
         ink_color = case when p_ink    is null then ink_color
                          else nullif(btrim(p_ink), '') end,
         bg_art    = case when p_art    is null then bg_art
                          else nullif(btrim(p_art), '') end,
         bg_image  = case when p_image  is null then bg_image
                          else nullif(btrim(p_image), '') end,
         bg_from   = case when p_from   is null then bg_from
                          else nullif(btrim(p_from), '') end,
         bg_credit = case when p_credit is null then bg_credit
                          else nullif(btrim(p_credit), '') end
   where staff_id = me.id;

  return public.ui_pref_get();
end;
$$;


-- ============================================================================
--  4-2. 取りこんだ画像の置き場所
--
--    お店（法人）ごとに仕切られます。よその法人からは見えません。
--    Supabase のプロジェクトによっては storage が無いこともあるので、
--    あるときだけ作ります。
-- ============================================================================

do $$
begin
  if to_regclass('storage.buckets') is not null then
    execute $q$
      insert into storage.buckets (id, name, public)
      values ('ui', 'ui', false)
      on conflict (id) do nothing
    $q$;

    execute $q$ drop policy if exists p_ui_bg_read on storage.objects $q$;
    execute $q$
      create policy p_ui_bg_read on storage.objects for select to authenticated
        using (bucket_id = 'ui'
               and (storage.foldername(name))[1] = app.my_tenant()::text)
    $q$;

    execute $q$ drop policy if exists p_ui_bg_write on storage.objects $q$;
    execute $q$
      create policy p_ui_bg_write on storage.objects for insert to authenticated
        with check (bucket_id = 'ui'
               and (storage.foldername(name))[1] = app.my_tenant()::text)
    $q$;

    execute $q$ drop policy if exists p_ui_bg_upd on storage.objects $q$;
    execute $q$
      create policy p_ui_bg_upd on storage.objects for update to authenticated
        using (bucket_id = 'ui'
               and (storage.foldername(name))[1] = app.my_tenant()::text)
    $q$;

    execute $q$ drop policy if exists p_ui_bg_del on storage.objects $q$;
    execute $q$
      create policy p_ui_bg_del on storage.objects for delete to authenticated
        using (bucket_id = 'ui'
               and (storage.foldername(name))[1] = app.my_tenant()::text)
    $q$;
  end if;
end $$;


-- ============================================================================
--  4-3. 画像を入れる場所の名前をもらう
--       （法人ごとに仕切るので、画面では決めさせません）
-- ============================================================================

create or replace function public.ui_bg_path(p_ext text default 'jpg')
returns text
language plpgsql stable security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if p_ext not in ('jpg','jpeg','png','webp') then
    raise exception 'その形の画像は入れられません';
  end if;
  return me.tenant_id::text || '/bg/' || me.id::text || '.' || p_ext;
end;
$$;

revoke all on function public.ui_bg_path(text) from anon;
grant execute on function public.ui_bg_path(text) to authenticated;


-- ============================================================================
--  5. すべて標準に戻す
-- ============================================================================

create or replace function public.ui_pref_reset()
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  delete from public.ui_pref where staff_id = me.id;
  return jsonb_build_object('preset', 'standard');
end;
$$;


revoke all on function public.ui_pref_get()   from anon;
revoke all on function
  public.ui_pref_set(text, text, text, integer, text, text, text, text, text, text) from anon;
revoke all on function public.ui_pref_reset() from anon;

grant execute on function public.ui_pref_get()   to authenticated;
grant execute on function
  public.ui_pref_set(text, text, text, integer, text, text, text, text, text, text)
  to authenticated;
grant execute on function public.ui_pref_reset() to authenticated;


-- ============================================================================
--  確認用
--    select public.ui_pref_get();          -- 画面からログインして呼びます
--    select * from public.ui_pref;         -- SQL Editor から、全員ぶん見えます
-- ============================================================================

-- ############################################################################
-- #
-- #   5. 在庫・発注   （021_zaiko.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通 / 在庫・発注パック
--  021_zaiko.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜020 を先に実行しておいてください）
--
--  ここで作るもの
--   ・消耗品・備品の台帳（ドリンク、おしぼり、アメニティ、事務用品 など）
--   ・在庫の出し入れ（仕入れ／使用／販売／廃棄／棚卸）
--   ・発注点を切ったものの、お知らせ
--   ・発注書（下書き → 発注ずみ → 納品）
--     ★ 納品にすると、その数だけ在庫が自動で増えます。
--     ★ 発注書は残るので、「いつ・何を・いくつ頼んだか」が後から追えます。
--
--  ★ 仕入値と発注は、店長以上の方だけが見られます。
--    スタッフさんは「使った」「捨てた」を入れるだけです。
--
--  ★ この表はナイトだんどり・キャストだんどりの両方から使えます。
--    お店（store_id）ごとに仕切られているので、混ざりません。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 商品（消耗品・備品）の台帳
-- ============================================================================
create table if not exists public.stock_product (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  name          text not null,
  maker         text,                                   -- メーカー・銘柄
  category      text,                                   -- 「ドリンク」「消耗品」など
  unit          text not null default '本',
  cost          integer not null default 0,             -- 仕入値（1つあたり・円）
  price         integer not null default 0,             -- 売値（お売りしない物は0）
  stock         numeric(10,2) not null default 0,       -- いまの在庫
  reorder_point numeric(10,2) not null default 0,       -- これを切ったらお知らせ
  reorder_qty   numeric(10,2) not null default 0,       -- 1回に頼む数の目安
  supplier      text,                                   -- 仕入先
  is_sale       boolean not null default false,         -- お客様にお売りする物か
  sort_no       integer not null default 100,
  note          text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (store_id, name)
);
create index if not exists idx_stock_product
  on public.stock_product(store_id, is_active, sort_no);

drop trigger if exists trg_touch_stock_product on public.stock_product;
create trigger trg_touch_stock_product before update on public.stock_product
for each row execute function app.touch_updated_at();


-- ============================================================================
--  2. 発注書
-- ============================================================================
create table if not exists public.stock_order (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  supplier      text,                                   -- 仕入先（名前だけ）
  order_date    date not null default current_date,
  deliver_date  date,                                   -- 納品の予定日
  -- draft（下書き）/ sent（発注ずみ）/ received（納品ずみ）/ cancel（取り消し）
  status        text not null default 'draft',
  note          text,
  total         integer not null default 0,             -- 仕入値の合計（目安）
  created_by    uuid references public.staff(id) on delete set null,
  sent_by       uuid references public.staff(id) on delete set null,
  sent_at       timestamptz,
  recv_by       uuid references public.staff(id) on delete set null,
  recv_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint stock_order_status_ck
    check (status in ('draft','sent','received','cancel'))
);
create index if not exists idx_stock_order
  on public.stock_order(store_id, order_date desc, created_at desc);

drop trigger if exists trg_touch_stock_order on public.stock_order;
create trigger trg_touch_stock_order before update on public.stock_order
for each row execute function app.touch_updated_at();


create table if not exists public.stock_order_line (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.stock_order(id) on delete cascade,
  product_id  uuid references public.stock_product(id) on delete set null,
  name        text not null,                            -- そのときの品名を残します
  unit        text,
  qty         numeric(10,2) not null default 1,         -- 頼んだ数
  recv_qty    numeric(10,2) not null default 0,         -- 実際に届いた数
  unit_price  integer not null default 0,
  amount      integer not null default 0,
  note        text,
  sort_no     integer not null default 100
);
create index if not exists idx_stock_order_line on public.stock_order_line(order_id);


--  数のかきかた（1.00 → 1、1.50 → 1.5）
create or replace function app.qty_text(n numeric)
returns text language sql immutable as $$
  select case when n is null then ''
              else rtrim(rtrim(to_char(n, 'FM9999990.99'), '0'), '.') end;
$$;


-- 行の金額は、入れたときに自動で計算します
create or replace function app.trg_stock_line_amt()
returns trigger language plpgsql set search_path = public, app as $$
begin
  new.amount := round(abs(coalesce(new.qty, 0)) * coalesce(new.unit_price, 0))::integer;
  return new;
end; $$;

drop trigger if exists trg_stock_line_amt on public.stock_order_line;
create trigger trg_stock_line_amt
before insert or update on public.stock_order_line
for each row execute function app.trg_stock_line_amt();


-- 発注書の合計は、行が変わるたびに入れ直します
create or replace function app.trg_stock_order_total()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_order uuid;
begin
  v_order := coalesce(new.order_id, old.order_id);
  update public.stock_order o
     set total = coalesce((select sum(l.amount)
                             from public.stock_order_line l
                            where l.order_id = v_order), 0)
   where o.id = v_order;
  return null;
end; $$;

drop trigger if exists trg_stock_order_total on public.stock_order_line;
create trigger trg_stock_order_total
after insert or update or delete on public.stock_order_line
for each row execute function app.trg_stock_order_total();


-- ============================================================================
--  3. 在庫の出し入れ
-- ============================================================================
create table if not exists public.stock_move (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  product_id    uuid not null references public.stock_product(id) on delete cascade,
  business_date date not null,
  -- in（仕入れ）/ sale（お客様へ販売）/ use（店内で使用）/ waste（廃棄）/ count（棚卸）
  kind          text not null default 'in',
  qty           numeric(10,2) not null default 0,       -- in は＋、sale/use/waste は−
  unit_price    integer not null default 0,
  amount        integer not null default 0,
  order_id      uuid references public.stock_order(id) on delete set null,
  staff_id      uuid references public.staff(id) on delete set null,
  note          text,
  created_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now(),
  constraint stock_move_kind_ck
    check (kind in ('in','sale','use','waste','count'))
);
create index if not exists idx_stock_move
  on public.stock_move(product_id, business_date desc, created_at desc);
create index if not exists idx_stock_move_store
  on public.stock_move(store_id, business_date);


create or replace function app.trg_stock_move_amt()
returns trigger language plpgsql set search_path = public, app as $$
begin
  new.amount := round(abs(coalesce(new.qty, 0)) * coalesce(new.unit_price, 0))::integer;
  return new;
end; $$;

drop trigger if exists trg_stock_move_amt on public.stock_move;
create trigger trg_stock_move_amt
before insert or update on public.stock_move
for each row execute function app.trg_stock_move_amt();


-- 在庫は、出し入れのたびに足し引きします
create or replace function app.trg_stock_move_stock()
returns trigger language plpgsql security definer set search_path = public, app as $$
begin
  if tg_op = 'INSERT' then
    if new.kind = 'count' then
      update public.stock_product set stock = new.qty where id = new.product_id;
    else
      update public.stock_product set stock = stock + new.qty where id = new.product_id;
    end if;
  elsif tg_op = 'DELETE' then
    if old.kind <> 'count' then
      update public.stock_product set stock = stock - old.qty where id = old.product_id;
    end if;
  end if;
  return null;
end; $$;

drop trigger if exists trg_stock_move_stock on public.stock_move;
create trigger trg_stock_move_stock
after insert or delete on public.stock_move
for each row execute function app.trg_stock_move_stock();


-- ============================================================================
--  4. 商品の登録と一覧
-- ============================================================================
create or replace function public.stock_product_save(
  p_store    uuid,
  p_id       uuid    default null,
  p_name     text    default null,
  p_maker    text    default null,
  p_category text    default null,
  p_unit     text    default null,
  p_cost     integer default null,
  p_price    integer default null,
  p_point    numeric default null,
  p_qty      numeric default null,
  p_supplier text    default null,
  p_is_sale  boolean default null,
  p_sort     integer default null,
  p_note     text    default null,
  p_active   boolean default null
) returns public.stock_product
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; p public.stock_product;
begin
  select * into me from app.me();
  if me.id is null and auth.uid() is not null then
    raise exception 'ログインが必要です';
  end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;

  if p_id is null then
    if nullif(btrim(coalesce(p_name, '')), '') is null then
      raise exception '品名を入れてください';
    end if;
    insert into public.stock_product(
      tenant_id, store_id, name, maker, category, unit, cost, price,
      reorder_point, reorder_qty, supplier, is_sale, sort_no, note)
    values (st.tenant_id, p_store, btrim(p_name), p_maker, p_category,
            coalesce(nullif(btrim(coalesce(p_unit, '')), ''), '個'),
            coalesce(p_cost, 0), coalesce(p_price, 0),
            coalesce(p_point, 0), coalesce(p_qty, 0),
            p_supplier, coalesce(p_is_sale, false),
            coalesce(p_sort, 100), p_note)
    returning * into p;
  else
    select * into p from public.stock_product where id = p_id;
    if not found then raise exception '商品が見つかりません'; end if;
    if p.store_id <> p_store then raise exception 'ほかの店舗の商品です'; end if;

    update public.stock_product set
      name          = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
      maker         = coalesce(p_maker, maker),
      category      = coalesce(p_category, category),
      unit          = coalesce(nullif(btrim(coalesce(p_unit, '')), ''), unit),
      cost          = coalesce(p_cost, cost),
      price         = coalesce(p_price, price),
      reorder_point = coalesce(p_point, reorder_point),
      reorder_qty   = coalesce(p_qty, reorder_qty),
      supplier      = coalesce(p_supplier, supplier),
      is_sale       = coalesce(p_is_sale, is_sale),
      sort_no       = coalesce(p_sort, sort_no),
      note          = coalesce(p_note, note),
      is_active     = coalesce(p_active, is_active)
    where id = p_id returning * into p;
  end if;
  return p;
end;
$$;


--  ★ 仕入値は、店長以上の方にだけお見せします。
create or replace function public.stock_product_list(
  p_store uuid, p_q text default null, p_all boolean default false)
returns table (
  id uuid, name text, maker text, category text, unit text,
  cost integer, price integer, stock numeric, reorder_point numeric,
  reorder_qty numeric, supplier text, is_sale boolean, low boolean,
  is_active boolean, note text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare q text; v_boss boolean;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  q := nullif(btrim(coalesce(p_q, '')), '');
  v_boss := (auth.uid() is null) or app.is_boss();

  return query
    select p.id, p.name, p.maker, p.category, p.unit,
           case when v_boss then p.cost else 0 end,
           p.price, p.stock, p.reorder_point, p.reorder_qty,
           case when v_boss then p.supplier else null end,
           p.is_sale,
           (p.reorder_point > 0 and p.stock <= p.reorder_point),
           p.is_active, p.note
      from public.stock_product p
     where p.store_id = p_store and (p_all or p.is_active)
       and (q is null or p.name ilike '%' || q || '%'
            or coalesce(p.maker, '') ilike '%' || q || '%'
            or coalesce(p.category, '') ilike '%' || q || '%')
     order by (p.reorder_point > 0 and p.stock <= p.reorder_point) desc,
              p.sort_no, p.name;
end;
$$;


-- ============================================================================
--  5. 在庫の出し入れ（画面から）
-- ============================================================================
create or replace function public.stock_move_add(
  p_product uuid,
  p_kind    text    default 'in',
  p_qty     numeric default 0,
  p_price   integer default null,
  p_note    text    default null,
  p_date    date    default null
) returns public.stock_move
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; p public.stock_product; st public.store;
        m public.stock_move; v_qty numeric; v_price integer;
begin
  select * into me from app.me();
  if me.id is null and auth.uid() is not null then
    raise exception 'ログインが必要です';
  end if;

  select * into p from public.stock_product where id = p_product;
  if not found then raise exception '商品が見つかりません'; end if;
  if not app.can_store(p.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if p_kind not in ('in','sale','use','waste','count') then
    raise exception 'その種類は選べません';
  end if;
  if p_kind <> 'count' and coalesce(p_qty, 0) = 0 then
    raise exception '数を入れてください';
  end if;

  select * into st from public.store where id = p.store_id;

  -- 仕入れと棚卸はそのまま、出ていくものはマイナスにします
  v_qty := abs(coalesce(p_qty, 0));
  if p_kind in ('sale','use','waste') then v_qty := -v_qty; end if;

  v_price := coalesce(p_price, case when p_kind = 'sale' then p.price else p.cost end);

  insert into public.stock_move(
    tenant_id, store_id, product_id, business_date, kind, qty, unit_price,
    note, created_by)
  values (st.tenant_id, p.store_id, p_product,
          coalesce(p_date, app.business_date(now(), st.day_cutoff)),
          p_kind, v_qty, v_price, p_note, me.id)
  returning * into m;

  return m;
end;
$$;


create or replace function public.stock_history(p_product uuid, p_limit integer default 50)
returns table (
  id uuid, business_date date, ymd text, kind text, kind_label text,
  qty numeric, unit_price integer, amount integer, note text, who text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare p public.stock_product; v_boss boolean;
begin
  select * into p from public.stock_product where id = p_product;
  if not found then raise exception '商品が見つかりません'; end if;
  if not app.can_store(p.store_id) then raise exception 'この店舗を見る権限がありません'; end if;
  v_boss := (auth.uid() is null) or app.is_boss();

  return query
    select m.id, m.business_date,
           to_char(m.business_date, 'MM/DD') || '（' || app.dow_ja(m.business_date) || '）',
           m.kind,
           case m.kind when 'in' then '仕入れ' when 'sale' then '販売'
                       when 'use' then '使用' when 'waste' then '廃棄'
                       else '棚卸' end,
           m.qty,
           case when v_boss then m.unit_price else 0 end,
           case when v_boss then m.amount else 0 end,
           m.note, s.name
      from public.stock_move m
      left join public.staff s on s.id = m.created_by
     where m.product_id = p_product
     order by m.business_date desc, m.created_at desc
     limit coalesce(p_limit, 50);
end;
$$;


-- ============================================================================
--  6. そろそろ頼むもの
-- ============================================================================
create or replace function public.stock_reorder_list(p_store uuid)
returns table (
  id uuid, name text, maker text, supplier text, unit text,
  stock numeric, reorder_point numeric, reorder_qty numeric,
  cost integer, order_cost integer
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  if auth.uid() is not null and not app.is_boss() then
    raise exception '発注の画面は、店長以上の方だけがご覧いただけます';
  end if;
  return query
    select p.id, p.name, p.maker, p.supplier, p.unit,
           p.stock, p.reorder_point, greatest(p.reorder_qty, 1), p.cost,
           round(greatest(p.reorder_qty, 1) * p.cost)::integer
      from public.stock_product p
     where p.store_id = p_store and p.is_active
       and p.reorder_point > 0 and p.stock <= p.reorder_point
     order by coalesce(p.supplier, ''), p.sort_no, p.name;
end;
$$;


-- 発注点を切っているものの件数（ホーム画面のお知らせ用・だれでも見られます）
create or replace function public.stock_low_count(p_store uuid)
returns integer
language plpgsql stable security definer set search_path = public, app
as $$
declare n integer;
begin
  if not app.can_store(p_store) then return 0; end if;
  select count(*) into n from public.stock_product p
   where p.store_id = p_store and p.is_active
     and p.reorder_point > 0 and p.stock <= p.reorder_point;
  return coalesce(n, 0);
end;
$$;


-- ============================================================================
--  7. 発注書
-- ============================================================================
create or replace function app.stock_boss_gate()
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if auth.uid() is null then return me; end if;         -- SQL Editor から
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception '発注は、店長以上の方だけが行えます';
  end if;
  return me;
end;
$$;


create or replace function public.stock_order_new(
  p_store uuid, p_supplier text default null, p_deliver date default null)
returns public.stock_order
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; o public.stock_order;
begin
  me := app.stock_boss_gate();
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;

  insert into public.stock_order(
    tenant_id, store_id, supplier, order_date, deliver_date, created_by)
  values (st.tenant_id, p_store, nullif(btrim(coalesce(p_supplier, '')), ''),
          current_date, coalesce(p_deliver, current_date + 2), me.id)
  returning * into o;
  return o;
end;
$$;


create or replace function public.stock_order_line_add(
  p_order   uuid,
  p_product uuid    default null,
  p_name    text    default null,
  p_qty     numeric default 1,
  p_price   integer default null,
  p_note    text    default null
) returns public.stock_order_line
language plpgsql security definer set search_path = public, app
as $$
declare o public.stock_order; p public.stock_product; l public.stock_order_line;
begin
  perform app.stock_boss_gate();

  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if o.status <> 'draft' then raise exception '下書きのときだけ、品を足せます'; end if;

  if p_product is not null then
    select * into p from public.stock_product
     where id = p_product and store_id = o.store_id;
    if not found then raise exception 'その商品は、この店舗にありません'; end if;
  end if;

  insert into public.stock_order_line(
    order_id, product_id, name, unit, qty, unit_price, note, sort_no)
  values (p_order, p_product,
          coalesce(nullif(btrim(coalesce(p_name, '')), ''), p.name, '（名前なし）'),
          coalesce(p.unit, '個'),
          greatest(coalesce(p_qty, 1), 0),
          coalesce(p_price, p.cost, 0), p_note,
          coalesce(p.sort_no, 100))
  returning * into l;
  return l;
end;
$$;


create or replace function public.stock_order_line_set(
  p_line uuid, p_qty numeric default null, p_price integer default null)
returns public.stock_order_line
language plpgsql security definer set search_path = public, app
as $$
declare o public.stock_order; l public.stock_order_line;
begin
  perform app.stock_boss_gate();
  select * into l from public.stock_order_line where id = p_line;
  if not found then raise exception 'その行が見つかりません'; end if;
  select * into o from public.stock_order where id = l.order_id;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if o.status not in ('draft','sent') then
    raise exception 'この発注書は、もう直せません';
  end if;

  update public.stock_order_line
     set qty        = coalesce(p_qty, qty),
         unit_price = coalesce(p_price, unit_price)
   where id = p_line returning * into l;
  return l;
end;
$$;


create or replace function public.stock_order_line_remove(p_line uuid)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare o public.stock_order; l public.stock_order_line;
begin
  perform app.stock_boss_gate();
  select * into l from public.stock_order_line where id = p_line;
  if not found then return false; end if;
  select * into o from public.stock_order where id = l.order_id;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if o.status <> 'draft' then raise exception '下書きのときだけ、消せます'; end if;

  delete from public.stock_order_line where id = p_line;
  return true;
end;
$$;


--  足りないものから、発注の下書きをまとめて作ります
--   ・仕入先ごとに1枚ずつ作ります（仕入先が空のものは「（仕入先なし）」で1枚）
--   ・すでにある下書きには足しません。毎回あたらしく作ります。
create or replace function public.stock_order_suggest(
  p_store uuid, p_supplier text default null)
returns table (order_id uuid, supplier text, lines integer, total integer)
language plpgsql security definer set search_path = public, app
as $$
#variable_conflict use_column
declare r record; o public.stock_order; n integer;
begin
  perform app.stock_boss_gate();
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;

  for r in
    select coalesce(nullif(btrim(coalesce(p.supplier, '')), ''), '') as sup
      from public.stock_product p
     where p.store_id = p_store and p.is_active
       and p.reorder_point > 0 and p.stock <= p.reorder_point
       and (p_supplier is null or coalesce(p.supplier, '') = p_supplier)
     group by 1
     order by 1
  loop
    o := public.stock_order_new(p_store, nullif(r.sup, ''), null);

    insert into public.stock_order_line(
      order_id, product_id, name, unit, qty, unit_price, note, sort_no)
    select o.id, p.id, p.name, p.unit,
           greatest(p.reorder_qty, 1), p.cost,
           '残り ' || app.qty_text(p.stock) || p.unit ||
           '（発注点 ' || app.qty_text(p.reorder_point) || p.unit || '）',
           p.sort_no
      from public.stock_product p
     where p.store_id = p_store and p.is_active
       and p.reorder_point > 0 and p.stock <= p.reorder_point
       and coalesce(nullif(btrim(coalesce(p.supplier, '')), ''), '') = r.sup;

    select count(*) into n from public.stock_order_line where order_id = o.id;
    select * into o from public.stock_order where id = o.id;

    order_id := o.id;
    supplier := coalesce(o.supplier, '（仕入先なし）');
    lines    := n;
    total    := o.total;
    return next;
  end loop;
end;
$$;


create or replace function public.stock_order_send(p_order uuid)
returns public.stock_order
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; o public.stock_order; n integer;
begin
  me := app.stock_boss_gate();
  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if o.status <> 'draft' then raise exception 'この発注書は、もう出ています'; end if;

  select count(*) into n from public.stock_order_line where order_id = p_order;
  if n = 0 then raise exception '発注する品が1つもありません'; end if;

  update public.stock_order
     set status = 'sent', sent_by = me.id, sent_at = now()
   where id = p_order returning * into o;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (o.tenant_id, o.store_id, me.id, 'stock_order_send', 'stock_order', o.id::text,
          jsonb_build_object('lines', n, 'total', o.total, 'supplier', o.supplier));
  return o;
end;
$$;


--  納品します。
--   p_lines … [{"line":"行のID","qty":6}, ...] のかたちで、届いた数を入れます。
--             省略すると、頼んだ数がそのまま届いたものとします。
create or replace function public.stock_order_receive(
  p_order uuid, p_lines jsonb default null, p_date date default null)
returns public.stock_order
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; o public.stock_order; st public.store; l record;
        v_date date; v_qty numeric; n integer := 0;
begin
  me := app.stock_boss_gate();
  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if o.status not in ('draft','sent') then
    raise exception 'この発注書は、もう納品ずみです';
  end if;

  select * into st from public.store where id = o.store_id;
  v_date := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  -- 届いた数を入れます
  if p_lines is not null then
    update public.stock_order_line l
       set recv_qty = greatest((x.value ->> 'qty')::numeric, 0)
      from jsonb_array_elements(p_lines) x
     where l.order_id = p_order
       and l.id = (x.value ->> 'line')::uuid;
    update public.stock_order_line
       set recv_qty = qty
     where order_id = p_order and recv_qty = 0
       and id not in (select (x.value ->> 'line')::uuid
                        from jsonb_array_elements(p_lines) x);
  else
    update public.stock_order_line set recv_qty = qty where order_id = p_order;
  end if;

  -- 届いたぶんだけ、在庫に入れます
  for l in
    select * from public.stock_order_line
     where order_id = p_order and product_id is not null and recv_qty > 0
  loop
    insert into public.stock_move(
      tenant_id, store_id, product_id, business_date, kind, qty, unit_price,
      order_id, note, created_by)
    values (o.tenant_id, o.store_id, l.product_id, v_date, 'in',
            l.recv_qty, l.unit_price, p_order, '発注ぶんの入荷', me.id);
    n := n + 1;
  end loop;

  update public.stock_order
     set status = 'received', recv_by = me.id, recv_at = now(),
         deliver_date = v_date
   where id = p_order returning * into o;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (o.tenant_id, o.store_id, me.id, 'stock_order_receive', 'stock_order', o.id::text,
          jsonb_build_object('lines', n, 'date', v_date));
  return o;
end;
$$;


create or replace function public.stock_order_cancel(p_order uuid)
returns public.stock_order
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; o public.stock_order;
begin
  me := app.stock_boss_gate();
  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if o.status = 'received' then
    raise exception '納品ずみのものは、取り消せません';
  end if;
  update public.stock_order set status = 'cancel' where id = p_order returning * into o;
  return o;
end;
$$;


create or replace function public.stock_order_list(
  p_store uuid, p_status text default null, p_limit integer default 50)
returns table (
  id uuid, order_date date, ymd text, deliver_date date, deliver_ymd text,
  supplier text, status text, status_label text,
  lines integer, total integer, note text, who text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  if auth.uid() is not null and not app.is_boss() then
    raise exception '発注の画面は、店長以上の方だけがご覧いただけます';
  end if;

  return query
    select o.id, o.order_date,
           to_char(o.order_date, 'MM/DD') || '（' || app.dow_ja(o.order_date) || '）',
           o.deliver_date,
           case when o.deliver_date is null then ''
                else to_char(o.deliver_date, 'MM/DD') || '（' ||
                     app.dow_ja(o.deliver_date) || '）' end,
           coalesce(o.supplier, '（仕入先なし）'),
           o.status,
           case o.status when 'draft' then '下書き' when 'sent' then '発注ずみ'
                         when 'received' then '納品ずみ' else '取り消し' end,
           (select count(*)::integer from public.stock_order_line l where l.order_id = o.id),
           o.total, o.note, s.name
      from public.stock_order o
      left join public.staff s on s.id = o.created_by
     where o.store_id = p_store
       and (p_status is null or o.status = p_status)
     order by o.order_date desc, o.created_at desc
     limit coalesce(p_limit, 50);
end;
$$;


create or replace function public.stock_order_get(p_order uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare o public.stock_order; st public.store; r jsonb;
begin
  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then raise exception 'この店舗を見る権限がありません'; end if;
  if auth.uid() is not null and not app.is_boss() then
    raise exception '発注の画面は、店長以上の方だけがご覧いただけます';
  end if;
  select * into st from public.store where id = o.store_id;

  select jsonb_build_object(
    'id', o.id,
    'store', st.name,
    'supplier', coalesce(o.supplier, '（仕入先なし）'),
    'order_date', to_char(o.order_date, 'YYYY/MM/DD'),
    'deliver_date', case when o.deliver_date is null then ''
                         else to_char(o.deliver_date, 'YYYY/MM/DD') end,
    'status', o.status,
    'status_label', case o.status when 'draft' then '下書き' when 'sent' then '発注ずみ'
                                  when 'received' then '納品ずみ' else '取り消し' end,
    'note', o.note,
    'total', o.total,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', l.id, 'product_id', l.product_id, 'name', l.name,
               'unit', l.unit, 'qty', l.qty, 'recv_qty', l.recv_qty,
               'unit_price', l.unit_price, 'amount', l.amount, 'note', l.note)
             order by l.sort_no, l.name)
        from public.stock_order_line l where l.order_id = o.id), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;


--  仕入先へそのまま送れる文面を作ります（LINE・メールに貼れます）
create or replace function public.stock_order_text(p_order uuid)
returns text
language plpgsql stable security definer set search_path = public, app
as $$
declare o public.stock_order; st public.store; v text; l record;
begin
  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then raise exception 'この店舗を見る権限がありません'; end if;
  if auth.uid() is not null and not app.is_boss() then
    raise exception '発注の画面は、店長以上の方だけがご覧いただけます';
  end if;
  select * into st from public.store where id = o.store_id;

  v := coalesce(o.supplier, '') || E'\n\n' ||
       'いつもお世話になっております。' || st.name || 'です。' || E'\n' ||
       '下記のとおり発注をお願いいたします。' || E'\n\n' ||
       '発注日　' || to_char(o.order_date, 'YYYY年MM月DD日') || E'\n';
  if o.deliver_date is not null then
    v := v || '納品希望　' || to_char(o.deliver_date, 'YYYY年MM月DD日') || E'\n';
  end if;
  v := v || E'\n';

  for l in
    select * from public.stock_order_line where order_id = p_order
     order by sort_no, name
  loop
    v := v || '・' || l.name || '　' ||
         app.qty_text(l.qty) || coalesce(l.unit, '') || E'\n';
  end loop;

  if nullif(btrim(coalesce(o.note, '')), '') is not null then
    v := v || E'\n' || o.note || E'\n';
  end if;
  v := v || E'\nお手数をおかけしますが、よろしくお願いいたします。' || E'\n' ||
       st.name || '　' || coalesce(st.tel, '');
  return v;
end;
$$;


create or replace function public.stock_order_note(p_order uuid, p_note text)
returns public.stock_order
language plpgsql security definer set search_path = public, app
as $$
declare o public.stock_order;
begin
  perform app.stock_boss_gate();
  select * into o from public.stock_order where id = p_order;
  if not found then raise exception '発注書が見つかりません'; end if;
  if not app.can_store(o.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  update public.stock_order set note = p_note where id = p_order returning * into o;
  return o;
end;
$$;


-- ============================================================================
--  8. ひな形（さいしょの商品を入れます）
--     p_kind  'night' … ナイトのお店むけ
--             'cast'  … 派遣型のお店むけ
-- ============================================================================
--  ★ 画面から押す「ひな形を入れる」は public のほう。
--    SQL Editor から入れるときは app.stock_seed_product_core をお使いください
--    （SQL Editor にはログインした方がいないため、権限の確認ができません）。
create or replace function app.stock_seed_product_core(
  p_store uuid, p_kind text default 'night')
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; n integer := 0; r record;
begin
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;

  for r in
    select * from (
      values
        --  種類    分類        品名                   単位  仕入  売値 在庫 発注点 頼む数  仕入先
        -- ナイト（お店で飲みものを出すところ）
        ('night', 'ドリンク',  'ビール（中瓶）',       '本', 350,  800,  48,  24,  24, '酒販店'),
        ('night', 'ドリンク',  '焼酎（麦・一升）',     '本', 1800, 0,     6,   3,   6, '酒販店'),
        ('night', 'ドリンク',  'ウイスキー（角）',     '本', 1600, 0,     6,   3,   6, '酒販店'),
        ('night', 'ドリンク',  'ソーダ水',             '本', 90,   0,    96,  48,  48, '酒販店'),
        ('night', 'ドリンク',  'ウーロン茶（2L）',     '本', 220,  0,    12,   6,  12, '酒販店'),
        ('night', 'フード',    '乾きもの（詰め合わせ）','袋', 180,  600,  40,  20,  30, '食材店'),
        ('night', '消耗品',    'おしぼり',             '本', 18,   0,   400, 200, 300, 'リネン'),
        ('night', '消耗品',    'コースター',           '枚', 6,    0,   600, 300, 500, '資材店'),
        ('night', '消耗品',    '氷（袋）',             '袋', 260,  0,    20,  10,  15, '製氷店'),
        ('night', '事務',      'レシート用紙',         '巻', 90,   0,    12,   6,  10, '事務用品'),
        -- キャスト（派遣型・待機所のあるところ）
        ('cast',  '消耗品',    'おしぼり',             '本', 18,   0,   400, 200, 300, 'リネン'),
        ('cast',  '消耗品',    'ボディタオル',         '枚', 55,   0,   200, 100, 150, 'リネン'),
        ('cast',  'アメニティ','シャンプー（業務用）', '本', 900,  0,     8,   4,   6, '資材店'),
        ('cast',  'アメニティ','ボディソープ（業務用）','本', 900,  0,     8,   4,   6, '資材店'),
        ('cast',  'アメニティ','歯ブラシ',             '本', 22,   0,   300, 150, 200, '資材店'),
        ('cast',  '消耗品',    'ゴム手袋（100枚）',    '箱', 780,  0,    10,   5,   6, '資材店'),
        ('cast',  '消耗品',    '消毒用アルコール',     '本', 620,  0,    12,   6,   8, '資材店'),
        ('cast',  '備品',      'タオル（フェイス）',   '枚', 180,  0,   160,  80, 100, 'リネン'),
        ('cast',  '備品',      'モバイルバッテリー',   '個', 2400, 0,    10,   6,   4, '量販店'),
        ('cast',  '事務',      'レシート用紙',         '巻', 90,   0,    12,   6,  10, '事務用品')
    ) as v(kind, category, name, unit, cost, price, stock, point, qty, supplier)
    where v.kind = coalesce(p_kind, 'night')
  loop
    insert into public.stock_product(
      tenant_id, store_id, name, category, unit, cost, price,
      stock, reorder_point, reorder_qty, supplier, is_sale, sort_no)
    values (st.tenant_id, p_store, r.name, r.category, r.unit, r.cost, r.price,
            r.stock, r.point, r.qty, r.supplier, (r.price > 0), 100 + n)
    on conflict (store_id, name) do nothing;
    n := n + 1;
  end loop;
  return n;
end;
$$;


create or replace function public.stock_seed_product(
  p_store uuid, p_kind text default 'night')
returns integer
language plpgsql security definer set search_path = public, app
as $$
begin
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  return app.stock_seed_product_core(p_store, p_kind);
end;
$$;


-- ============================================================================
--  9. 行の見せ方（RLS）と権限
-- ============================================================================
alter table public.stock_product    enable row level security;
alter table public.stock_move       enable row level security;
alter table public.stock_order      enable row level security;
alter table public.stock_order_line enable row level security;

do $$
declare t text;
begin
  foreach t in array array['stock_product','stock_move','stock_order'] loop
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format(
      'create policy p_%1$s on public.%1$s for all
         using (tenant_id = app.my_tenant() and app.can_store(store_id))
         with check (tenant_id = app.my_tenant() and app.can_store(store_id))', t);
  end loop;
end $$;

drop policy if exists p_stock_order_line on public.stock_order_line;
create policy p_stock_order_line on public.stock_order_line for all
  using (exists (select 1 from public.stock_order o
                  where o.id = order_id
                    and o.tenant_id = app.my_tenant()
                    and app.can_store(o.store_id)))
  with check (exists (select 1 from public.stock_order o
                  where o.id = order_id
                    and o.tenant_id = app.my_tenant()
                    and app.can_store(o.store_id)));

grant select, insert, update, delete on
  public.stock_product, public.stock_move,
  public.stock_order, public.stock_order_line
to authenticated;

revoke all on function app.stock_boss_gate() from anon, authenticated;
revoke all on function app.stock_seed_product_core(uuid, text) from anon, authenticated;

--  ログインしていない方からは、1つも呼べないようにします
revoke all on function
  public.stock_product_save(uuid, uuid, text, text, text, text, integer, integer,
                            numeric, numeric, text, boolean, integer, text, boolean),
  public.stock_product_list(uuid, text, boolean),
  public.stock_move_add(uuid, text, numeric, integer, text, date),
  public.stock_history(uuid, integer),
  public.stock_reorder_list(uuid),
  public.stock_low_count(uuid),
  public.stock_order_new(uuid, text, date),
  public.stock_order_line_add(uuid, uuid, text, numeric, integer, text),
  public.stock_order_line_set(uuid, numeric, integer),
  public.stock_order_line_remove(uuid),
  public.stock_order_suggest(uuid, text),
  public.stock_order_send(uuid),
  public.stock_order_receive(uuid, jsonb, date),
  public.stock_order_cancel(uuid),
  public.stock_order_list(uuid, text, integer),
  public.stock_order_get(uuid),
  public.stock_order_text(uuid),
  public.stock_order_note(uuid, text),
  public.stock_seed_product(uuid, text)
from public, anon;

grant execute on function
  public.stock_product_save(uuid, uuid, text, text, text, text, integer, integer,
                            numeric, numeric, text, boolean, integer, text, boolean),
  public.stock_product_list(uuid, text, boolean),
  public.stock_move_add(uuid, text, numeric, integer, text, date),
  public.stock_history(uuid, integer),
  public.stock_reorder_list(uuid),
  public.stock_low_count(uuid),
  public.stock_order_new(uuid, text, date),
  public.stock_order_line_add(uuid, uuid, text, numeric, integer, text),
  public.stock_order_line_set(uuid, numeric, integer),
  public.stock_order_line_remove(uuid),
  public.stock_order_suggest(uuid, text),
  public.stock_order_send(uuid),
  public.stock_order_receive(uuid, jsonb, date),
  public.stock_order_cancel(uuid),
  public.stock_order_list(uuid, text, integer),
  public.stock_order_get(uuid),
  public.stock_order_text(uuid),
  public.stock_order_note(uuid, text),
  public.stock_seed_product(uuid, text)
to authenticated;

notify pgrst, 'reload schema';


-- ============================================================================
--  確認用（店舗IDを入れかえてお使いください）
--
--   -- ひな形を入れる（SQL Editor から入れるときは app のほう）
--   select app.stock_seed_product_core('店舗ID', 'night');   -- ナイト
--   select app.stock_seed_product_core('店舗ID', 'cast');    -- キャスト
--
--   -- 入ったかどうかの確認
--   select name, category, stock, reorder_point, cost
--     from public.stock_product where store_id = '店舗ID' order by sort_no;
--
--  ※ stock_product_list などは「ログインした方」が前提の関数です。
--    SQL Editor から呼ぶと 0件 になりますが、画面からはきちんと出ます。
-- ============================================================================

-- ############################################################################
-- #
-- #   6. お店のえらびかた   （022_mise.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通 / お店のえらびかた
--  022_mise.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜021 を先に実行しておいてください）
--
--  なおすこと
--   画面を更新したり、上のボタンでページを移ったりすると、
--   えらんでいたお店が別のお店（しかも別の業種のお店）に
--   入れかわってしまうことがありました。
--
--   原因は2つです。
--     1. お店の一覧に、ほかの業種のお店もまざって出ていた
--     2. 「さっきえらんだお店」の覚え場所が、業種でひとつづきだった
--
--   ここでは 1 をなおします。
--     ・お店に「業種」の印をつけます（もう付いているお店はそのまま）
--     ・印がまだ無いお店は、中に入っているデータから推しはかって付けます
--     ・画面は store_list() でお店を取るようにし、
--       その業種のお店だけが出るようにします
--
--   2 は、画面のJS（common.js / kyotsu.js / app.js）でなおしてあります。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. お店に「業種」の印をつける場所
-- ============================================================================
alter table public.store add column if not exists industry text;

comment on column public.store.industry is
  'このお店をどの画面で出すか。night / cast / food / salon / pet。'
  'null のときは、どの画面にも出します（まだ決めていないお店）。';

create index if not exists idx_store_industry on public.store(industry, is_active);


-- ============================================================================
--  2. 印がまだ無いお店に、中のデータから印をつけます
--
--     いちばん行数の多い業種を、そのお店の業種とみなします。
--     どの業種のデータも無いお店は、そのまま（null）にしておきます。
--     入れていない業種の表は、とばします。
-- ============================================================================
create or replace function app.store_industry_guess(p_all boolean default false)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare
  v record; r record; cnt jsonb; c bigint; best text; n integer := 0;
begin
  for v in
    select id from public.store
     where p_all or industry is null
  loop
    cnt := '{}'::jsonb;

    for r in
      select * from (values
        ('night', 'night_visit'),  ('night', 'night_cast'),   ('night', 'night_menu'),
        ('cast',  'cast_booking'), ('cast',  'cast_member'),  ('cast',  'cast_room'),
        ('food',  'food_menu'),    ('food',  'food_staff'),   ('food',  'food_purchase'),
        ('salon', 'salon_menu'),   ('salon', 'salon_staff'),  ('salon', 'salon_sale'),
        ('pet',   'pet_menu'),     ('pet',   'pet_staff'),    ('pet',   'pet_sale')
      ) as x(k, t)
    loop
      if to_regclass('public.' || r.t) is null then
        continue;
      end if;
      execute format('select count(*) from public.%I where store_id = $1', r.t)
        into c using v.id;
      cnt := jsonb_set(cnt, array[r.k],
                       to_jsonb(coalesce((cnt ->> r.k)::bigint, 0) + coalesce(c, 0)));
    end loop;

    best := null;
    select e.key into best
      from jsonb_each_text(cnt) e
     where e.value::bigint > 0
     order by e.value::bigint desc, e.key
     limit 1;

    if best is not null then
      update public.store set industry = best where id = v.id;
      n := n + 1;
    end if;
  end loop;

  return n;
end;
$$;

revoke all on function app.store_industry_guess(boolean) from anon, authenticated;

--  いま入っているお店に、さっそく印をつけます
do $$
declare n integer;
begin
  n := app.store_industry_guess(false);
  raise notice '業種の印をつけたお店： % 件', n;
end $$;


-- ============================================================================
--  3. 画面にお店をならべるための関数
--
--     ・ログインしている方が見てよいお店だけ
--     ・その業種のお店だけ（印がまだ無いお店も、念のため出します）
--     ・印のあるお店を先に、そのあとに印の無いお店
-- ============================================================================
create or replace function public.store_list(p_kind text default null)
returns setof public.store
language plpgsql stable security definer set search_path = public, app
as $$
begin
  return query
    select s.*
      from public.store s
     where s.is_active
       and app.can_store(s.id)
       and (p_kind is null or s.industry is null or s.industry = p_kind)
     order by (s.industry is null), s.name;
end;
$$;


-- ============================================================================
--  4. お店の業種を、あとから変えるとき（設定の画面から使います）
-- ============================================================================
create or replace function public.store_industry_set(p_store uuid, p_kind text)
returns public.store
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; s public.store;
begin
  select * into me from app.me();
  if auth.uid() is not null then
    if me.id is null then raise exception 'ログインが必要です'; end if;
    if me.role not in ('owner','manager') then
      raise exception 'お店の設定を変えられるのは、店長以上の方だけです';
    end if;
  end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if p_kind is not null and p_kind not in ('night','cast','food','salon','pet') then
    raise exception 'その業種は選べません';
  end if;

  update public.store set industry = nullif(btrim(coalesce(p_kind, '')), '')
   where id = p_store returning * into s;
  return s;
end;
$$;


-- ============================================================================
--  5. 権限
-- ============================================================================
revoke all on function
  public.store_list(text),
  public.store_industry_set(uuid, text)
from public, anon;

grant execute on function
  public.store_list(text),
  public.store_industry_set(uuid, text)
to authenticated;

notify pgrst, 'reload schema';


-- ============================================================================
--  確認用
--
--   -- どのお店が、どの業種になっているか
--   select name, coalesce(industry, '（まだ決めていません）') as 業種
--     from public.store order by industry nulls last, name;
--
--   -- 手で決めたいとき（店舗IDと業種を入れかえてください）
--   update public.store set industry = 'night' where id = '店舗ID';
--
--   -- 中のデータから、ぜんぶ付け直したいとき
--   select app.store_industry_guess(true);
-- ============================================================================


-- ############################################################################
-- #
-- #   7. 清掃・やること   （023_souji.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通 / 清掃・やることパック
--  023_souji.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜022 を先に実行しておいてください）
--
--  ここで作るもの
--   ・清掃する場所の台帳（業種ごとのひな形つき）
--   ・「きょうやること」（毎日／週1／月1／年1を、周期から自動で出します）
--   ・やった記録（だれが・いつ）
--   ・業者さんのクリーニングのご案内
--     前に業者さんが入った日から決めた月数（既定は12か月）がたつと、
--     「そろそろ業者さんに見てもらう時期です」と出ます。
--   ・その日だけの追加（3つまで）
--   ・紙に出すための、1日ぶんのまとめ
--
--  ★ ハンコの運用にも、チェックの運用にも、どちらにも使えます。
--    紙に出すときに、ハンコ欄を出すかどうかを選べます。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 清掃する場所の台帳
-- ============================================================================
create table if not exists public.clean_spot (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant(id) on delete cascade,
  store_id     uuid not null references public.store(id) on delete cascade,
  name         text not null,
  area         text,                                  -- 「客席」「厨房」「水まわり」など
  -- daily（毎日）/ weekly（週1）/ monthly（月1）/ quarterly（3か月）/ yearly（年1）
  cycle        text not null default 'daily',
  dow          integer,                               -- 週1のとき、何曜日か（0=日）
  dom          integer,                               -- 月1のとき、何日か
  --  業者さんのクリーニングの間隔（月）。0 なら、ご案内を出しません。
  pro_months   integer not null default 0,
  pro_last     date,                                  -- 前に業者さんが入った日
  pro_note     text,                                  -- 「○○クリーニング 090-…」など
  how          text,                                  -- やり方のひとこと
  sort_no      integer not null default 100,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (store_id, name),
  constraint clean_spot_cycle_ck
    check (cycle in ('daily','weekly','monthly','quarterly','yearly'))
);
create index if not exists idx_clean_spot on public.clean_spot(store_id, is_active, sort_no);

drop trigger if exists trg_touch_clean_spot on public.clean_spot;
create trigger trg_touch_clean_spot before update on public.clean_spot
for each row execute function app.touch_updated_at();


-- ============================================================================
--  2. やった記録
--     spot_id が空の行は、その日だけの追加ぶんです（spot_name に名前が入ります）
-- ============================================================================
create table if not exists public.clean_log (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant(id) on delete cascade,
  store_id      uuid not null references public.store(id) on delete cascade,
  spot_id       uuid references public.clean_spot(id) on delete cascade,
  spot_name     text,                                 -- 追加ぶんの名前
  business_date date not null,
  kind          text not null default 'self',         -- self（自分たち）/ pro（業者さん）
  staff_id      uuid references public.staff(id) on delete set null,
  note          text,
  created_by    uuid references public.staff(id) on delete set null,
  created_at    timestamptz not null default now(),
  constraint clean_log_kind_ck check (kind in ('self','pro')),
  constraint clean_log_what_ck
    check (spot_id is not null or nullif(btrim(coalesce(spot_name, '')), '') is not null)
);
create index if not exists idx_clean_log
  on public.clean_log(store_id, business_date desc);
create index if not exists idx_clean_log_spot
  on public.clean_log(spot_id, business_date desc);

--  同じ場所を、同じ日に二重に記録しないようにします
create unique index if not exists uq_clean_log_spot_day
  on public.clean_log(spot_id, business_date, kind) where spot_id is not null;


--  業者さんの記録が入ったら、その場所の「前に入った日」を更新します
create or replace function app.trg_clean_pro()
returns trigger language plpgsql security definer set search_path = public, app as $$
begin
  if tg_op = 'INSERT' and new.kind = 'pro' and new.spot_id is not null then
    update public.clean_spot
       set pro_last = greatest(coalesce(pro_last, new.business_date), new.business_date)
     where id = new.spot_id;
  elsif tg_op = 'DELETE' and old.kind = 'pro' and old.spot_id is not null then
    update public.clean_spot s
       set pro_last = (select max(l.business_date) from public.clean_log l
                        where l.spot_id = old.spot_id and l.kind = 'pro')
     where s.id = old.spot_id;
  end if;
  return null;
end; $$;

drop trigger if exists trg_clean_pro on public.clean_log;
create trigger trg_clean_pro
after insert or delete on public.clean_log
for each row execute function app.trg_clean_pro();


-- ============================================================================
--  3. その日にやることかどうかの判定
-- ============================================================================
create or replace function app.clean_is_due(
  p_cycle text, p_dow integer, p_dom integer, p_last date, p_date date)
returns boolean
language sql immutable as $$
  select case p_cycle
    when 'daily'   then true
    when 'weekly'  then (p_dow is null and (p_last is null or p_date - p_last >= 7))
                        or (p_dow is not null and extract(dow from p_date)::int = p_dow)
    when 'monthly' then (p_dom is null and (p_last is null or p_date - p_last >= 30))
                        or (p_dom is not null and extract(day from p_date)::int = p_dom)
    when 'quarterly' then (p_last is null or p_date - p_last >= 90)
    when 'yearly'    then (p_last is null or p_date - p_last >= 365)
    else true end;
$$;


-- ============================================================================
--  4. きょうやること
--
--   done    … その日、もう記録が入っているか
--   due     … その日にやる日か
--   late    … 予定より遅れているか（何日あいているか）
-- ============================================================================
create or replace function public.clean_today(p_store uuid, p_date date default null)
returns table (
  id uuid, name text, area text, cycle text, cycle_label text, how text,
  last_date date, last_label text, days integer,
  due boolean, done boolean, late boolean,
  pro_months integer, pro_last date, pro_due boolean, pro_days integer, pro_note text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare st public.store; d date;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  d := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  return query
    with last_self as (
      select l.spot_id, max(l.business_date) as d
        from public.clean_log l
       where l.store_id = p_store and l.kind = 'self' and l.business_date < d
       group by l.spot_id
    ), today_done as (
      select distinct l.spot_id
        from public.clean_log l
       where l.store_id = p_store and l.business_date = d and l.spot_id is not null
    )
    select s.id, s.name, s.area, s.cycle,
           case s.cycle when 'daily' then '毎日' when 'weekly' then '週に1回'
                        when 'monthly' then '月に1回' when 'quarterly' then '3か月に1回'
                        else '年に1回' end,
           s.how,
           ls.d,
           case when ls.d is null then 'まだ記録がありません'
                else to_char(ls.d, 'MM/DD') || '（' || app.dow_ja(ls.d) || '）' end,
           case when ls.d is null then null else (d - ls.d)::integer end,
           app.clean_is_due(s.cycle, s.dow, s.dom, ls.d, d),
           (td.spot_id is not null),
           case when ls.d is null then false else
             (d - ls.d) > case s.cycle when 'daily' then 1 when 'weekly' then 9
                                       when 'monthly' then 38 when 'quarterly' then 100
                                       else 380 end end,
           s.pro_months, s.pro_last,
           (s.pro_months > 0 and (s.pro_last is null
                                  or d - s.pro_last >= s.pro_months * 30)),
           case when s.pro_last is null then null else (d - s.pro_last)::integer end,
           s.pro_note
      from public.clean_spot s
      left join last_self ls on ls.spot_id = s.id
      left join today_done td on td.spot_id = s.id
     where s.store_id = p_store and s.is_active
     order by (td.spot_id is not null),
              app.clean_is_due(s.cycle, s.dow, s.dom, ls.d, d) desc,
              s.sort_no, s.name;
end;
$$;


-- ============================================================================
--  5. 業者さんのクリーニングのご案内
-- ============================================================================
create or replace function public.clean_pro_due(p_store uuid)
returns table (
  id uuid, name text, area text, pro_months integer, pro_last date,
  last_label text, days integer, over_days integer, pro_note text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  return query
    select s.id, s.name, s.area, s.pro_months, s.pro_last,
           case when s.pro_last is null then 'まだ記録がありません'
                else to_char(s.pro_last, 'YYYY年MM月DD日') end,
           case when s.pro_last is null then null
                else (current_date - s.pro_last)::integer end,
           case when s.pro_last is null then null
                else (current_date - s.pro_last - s.pro_months * 30)::integer end,
           s.pro_note
      from public.clean_spot s
     where s.store_id = p_store and s.is_active and s.pro_months > 0
       and (s.pro_last is null or current_date - s.pro_last >= s.pro_months * 30)
     order by s.pro_last nulls first, s.sort_no, s.name;
end;
$$;


--  ホーム画面のお知らせ用（だれでも見られます）
create or replace function public.clean_alert_count(p_store uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare st public.store; d date; v_todo integer; v_pro integer;
begin
  if not app.can_store(p_store) then return jsonb_build_object('todo', 0, 'pro', 0); end if;
  select * into st from public.store where id = p_store;
  d := coalesce(app.business_date(now(), st.day_cutoff), current_date);

  select count(*) into v_todo from public.clean_today(p_store, d) t
   where t.due and not t.done;
  select count(*) into v_pro from public.clean_pro_due(p_store);

  return jsonb_build_object('todo', coalesce(v_todo, 0), 'pro', coalesce(v_pro, 0));
end;
$$;


-- ============================================================================
--  6. やった／やっていない を入れる
-- ============================================================================
create or replace function public.clean_done(
  p_store uuid,
  p_spot  uuid    default null,
  p_name  text    default null,
  p_date  date    default null,
  p_kind  text    default 'self',
  p_note  text    default null
) returns public.clean_log
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; l public.clean_log; d date;
begin
  select * into me from app.me();
  if me.id is null and auth.uid() is not null then
    raise exception 'ログインが必要です';
  end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if p_kind not in ('self','pro') then raise exception 'その種類は選べません'; end if;
  if p_spot is null and nullif(btrim(coalesce(p_name, '')), '') is null then
    raise exception 'どこを清掃したかを入れてください';
  end if;

  select * into st from public.store where id = p_store;
  d := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  if p_spot is not null then
    if not exists (select 1 from public.clean_spot
                    where id = p_spot and store_id = p_store) then
      raise exception 'その場所は、この店舗にありません';
    end if;
    delete from public.clean_log
     where spot_id = p_spot and business_date = d and kind = p_kind;
  end if;

  insert into public.clean_log(
    tenant_id, store_id, spot_id, spot_name, business_date, kind,
    staff_id, note, created_by)
  values (st.tenant_id, p_store, p_spot,
          nullif(btrim(coalesce(p_name, '')), ''), d, p_kind,
          me.id, p_note, me.id)
  returning * into l;

  return l;
end;
$$;


create or replace function public.clean_undo(
  p_store uuid, p_spot uuid, p_date date default null, p_kind text default 'self')
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; d date;
begin
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  select * into st from public.store where id = p_store;
  d := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  delete from public.clean_log
   where store_id = p_store and spot_id = p_spot
     and business_date = d and kind = coalesce(p_kind, 'self');
  return true;
end;
$$;


--  その日だけの追加ぶんを、消します
create or replace function public.clean_extra_remove(p_log uuid)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare l public.clean_log;
begin
  select * into l from public.clean_log where id = p_log;
  if not found then return false; end if;
  if not app.can_store(l.store_id) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  delete from public.clean_log where id = p_log;
  return true;
end;
$$;


-- ============================================================================
--  7. 場所の台帳（見る・直す）
-- ============================================================================
create or replace function public.clean_spot_list(p_store uuid, p_all boolean default false)
returns setof public.clean_spot
language plpgsql stable security definer set search_path = public, app
as $$
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  return query
    select s.* from public.clean_spot s
     where s.store_id = p_store and (p_all or s.is_active)
     order by s.sort_no, s.name;
end;
$$;


create or replace function public.clean_spot_save(
  p_store    uuid,
  p_id       uuid    default null,
  p_name     text    default null,
  p_area     text    default null,
  p_cycle    text    default null,
  p_dow      integer default null,
  p_dom      integer default null,
  p_pro      integer default null,
  p_pro_last date    default null,
  p_pro_note text    default null,
  p_how      text    default null,
  p_sort     integer default null,
  p_active   boolean default null
) returns public.clean_spot
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; s public.clean_spot;
begin
  select * into me from app.me();
  if auth.uid() is not null then
    if me.id is null then raise exception 'ログインが必要です'; end if;
    if me.role not in ('owner','manager') then
      raise exception '清掃する場所の設定は、店長以上の方だけです';
    end if;
  end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if p_cycle is not null
     and p_cycle not in ('daily','weekly','monthly','quarterly','yearly') then
    raise exception 'その周期は選べません';
  end if;
  select * into st from public.store where id = p_store;

  if p_id is null then
    if nullif(btrim(coalesce(p_name, '')), '') is null then
      raise exception '場所の名前を入れてください';
    end if;
    insert into public.clean_spot(
      tenant_id, store_id, name, area, cycle, dow, dom,
      pro_months, pro_last, pro_note, how, sort_no)
    values (st.tenant_id, p_store, btrim(p_name), p_area,
            coalesce(p_cycle, 'daily'), p_dow, p_dom,
            coalesce(p_pro, 0), p_pro_last, p_pro_note, p_how,
            coalesce(p_sort, 100))
    returning * into s;
  else
    select * into s from public.clean_spot where id = p_id;
    if not found then raise exception 'その場所が見つかりません'; end if;
    if s.store_id <> p_store then raise exception 'ほかの店舗の場所です'; end if;

    update public.clean_spot set
      name       = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
      area       = coalesce(p_area, area),
      cycle      = coalesce(p_cycle, cycle),
      dow        = case when p_cycle is not null then p_dow else coalesce(p_dow, dow) end,
      dom        = case when p_cycle is not null then p_dom else coalesce(p_dom, dom) end,
      pro_months = coalesce(p_pro, pro_months),
      pro_last   = coalesce(p_pro_last, pro_last),
      pro_note   = coalesce(p_pro_note, pro_note),
      how        = coalesce(p_how, how),
      sort_no    = coalesce(p_sort, sort_no),
      is_active  = coalesce(p_active, is_active)
    where id = p_id returning * into s;
  end if;
  return s;
end;
$$;


-- ============================================================================
--  8. 紙に出すための、1日ぶんのまとめ
--
--   p_extra … 追加ぶんを、いくつぶん空欄で出すか（0〜3）
-- ============================================================================
create or replace function public.clean_sheet(
  p_store uuid, p_date date default null, p_extra integer default 3)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare st public.store; d date; r jsonb;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  d := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  select jsonb_build_object(
    'store', st.name,
    'date',  to_char(d, 'YYYY年MM月DD日') || '（' || app.dow_ja(d) || '）',
    'ymd',   to_char(d, 'YYYY-MM-DD'),
    'extra_slots', greatest(least(coalesce(p_extra, 3), 3), 0),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'name', t.name, 'area', coalesce(t.area, ''),
               'cycle', t.cycle_label, 'how', coalesce(t.how, ''),
               'done', t.done, 'late', t.late,
               'last', t.last_label)
             order by coalesce(sp.area, 'んん'), sp.sort_no, t.name)
        from public.clean_today(p_store, d) t
        join public.clean_spot sp on sp.id = t.id
       where t.due), '[]'::jsonb),
    'extras', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', l.id, 'name', l.spot_name, 'note', coalesce(l.note, ''))
             order by l.created_at)
        from public.clean_log l
       where l.store_id = p_store and l.business_date = d and l.spot_id is null),
      '[]'::jsonb),
    'pro', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', p.name, 'last', p.last_label, 'note', coalesce(p.pro_note, ''),
               'months', p.pro_months)
             order by p.pro_last nulls first, p.name)
        from public.clean_pro_due(p_store) p
       where p.pro_last is not null), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;


-- ============================================================================
--  9. 業種ごとのひな形
--
--   p_kind を省くと、そのお店の industry を見ます。
--   どの業種にも入る「共通」のぶんと、業種ごとのぶんを入れます。
--
--   pro_months …  0 = 業者さんのご案内なし
--                 3 = 3か月に1回（グリストラップなど）
--                 6 = 半年に1回（換気扇・排水など）
--                12 = 年に1回（エアコン・ダクト・絨毯など）
-- ============================================================================
create or replace function app.clean_seed_core(p_store uuid, p_kind text default null)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; v_kind text; n integer := 0; r record;
begin
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;
  v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), st.industry, 'night');

  for r in
    select * from (values
      --  業種  区分        場所                        周期        業者(月) やり方
      ('*',    '水まわり', 'トイレ（便器・手洗い・床）', 'daily',       12, '便器・床・手洗い・鏡。備品の補充も'),
      ('*',    '客席',     '床（掃き・拭き）',           'daily',        0, ''),
      ('*',    '客席',     'テーブル・カウンター',       'daily',        0, ''),
      ('*',    '入口',     '入口まわり・看板',           'daily',        0, 'ガラス・のぼり・灰皿まわり'),
      ('*',    '空調',     'エアコン（フィルター）',     'weekly',      12, 'フィルターを外して水洗い。年1回は業者さんへ'),
      ('*',    '水まわり', '手洗い場・洗面',             'daily',        0, ''),
      ('*',    'ごみ',     'ゴミ置き場・ゴミ箱',         'daily',        0, '生ゴミは持ち出し。ふたの裏も'),
      ('*',    '客席',     '窓・ガラス・鏡',             'weekly',       0, ''),
      ('*',    '客席',     '照明・電球',                 'monthly',      0, '切れかけは先に替える'),
      ('*',    '水まわり', '排水溝・排水トラップ',       'weekly',       6, 'においが出る前に'),
      ('*',    '客席',     '冷蔵庫（中・パッキン）',     'weekly',       0, ''),
      ('*',    '事務',     'レジまわり・事務机',         'weekly',       0, ''),

      -- ナイト
      ('night', 'カウンター', 'カウンター・バックバー',  'daily',        0, ''),
      ('night', 'カウンター', 'グラス棚・ボトル棚',      'weekly',       0, 'ほこりと指紋'),
      ('night', '厨房',       '製氷機',                  'weekly',      12, '受け皿と庫内。年1回は分解洗浄を業者さんへ'),
      ('night', '客席',       'ソファ・椅子',            'weekly',      12, 'すき間のゴミ。年1回はクリーニングを'),
      ('night', '客席',       '絨毯・カーペット',        'daily',       12, '毎日は掃除機。年1回は業者さんの洗浄を'),
      ('night', '空調',       'ダクト・換気扇',          'monthly',     12, 'におい・煙のこもりが出たら早めに'),
      ('night', '客席',       'カラオケ機器・マイク',    'daily',        0, 'マイクは毎日、除菌シートで'),
      ('night', '水まわり',   'おしぼり庫・タオル庫',    'weekly',       0, ''),

      -- キャスト
      ('cast',  '待機所',   '待機所（床・机・ソファ）',  'daily',        0, ''),
      ('cast',  '水まわり', 'シャワー室',                'daily',       12, '排水口の髪の毛。年1回はカビの洗浄を'),
      ('cast',  '水まわり', '洗濯機（槽の洗浄）',        'monthly',     12, '月1回は槽クリーナー。年1回は分解洗浄を'),
      ('cast',  'リネン',   '寝具・タオル・リネン',      'daily',        0, '使ったぶんはその日のうちに'),
      ('cast',  '部屋',     'お部屋（ベッド・床）',      'daily',        0, ''),
      ('cast',  '事務',     '事務所・金庫まわり',        'weekly',       0, ''),
      ('cast',  '送迎',     '送迎車（車内）',            'weekly',      12, 'シート・足もと。年1回はクリーニングを'),

      -- フード
      ('food',  '厨房',     '厨房の床・排水',            'daily',        0, '油は残さない'),
      ('food',  '厨房',     '換気扇・グリスフィルター',  'weekly',       6, '半年に1回は業者さんの洗浄を'),
      ('food',  '厨房',     'ダクト',                    'quarterly',   12, '火災予防のため、年1回は業者さんへ'),
      ('food',  '厨房',     'グリストラップ',            'weekly',       3, '3か月に1回は業者さんの汲み取りを'),
      ('food',  '厨房',     '製氷機',                    'weekly',      12, '年1回は分解洗浄を業者さんへ'),
      ('food',  '厨房',     '冷蔵・冷凍庫',              'weekly',       0, '庫内温度の記録もあわせて'),
      ('food',  '厨房',     'フライヤー（油）',          'daily',        0, ''),
      ('food',  '厨房',     '食器洗浄機',                'daily',       12, '残菜かごとノズル'),
      ('food',  '厨房',     'まな板・包丁の消毒',        'daily',        0, ''),
      ('food',  '客席',     'ドリンクディスペンサー',    'daily',       12, 'ノズルは毎日はずして洗う'),

      -- サロン
      ('salon', '水まわり', 'シャンプー台',              'daily',       12, 'ヘッドとホース。年1回は配管の洗浄を'),
      ('salon', '水まわり', '排水・毛髪キャッチャー',    'daily',        6, '半年に1回は業者さんの高圧洗浄を'),
      ('salon', '客席',     'セット面・鏡',              'daily',        0, ''),
      ('salon', '客席',     '床（毛の掃除）',            'daily',        0, 'お客様ごとに'),
      ('salon', '器具',     'ハサミ・コーム・器具の消毒','daily',        0, '使うたびに'),
      ('salon', '器具',     'ドライヤー（フィルター）',  'weekly',       0, 'ほこりが詰まると熱がこもります'),
      ('salon', '器具',     'タオル蒸し器',              'weekly',       0, ''),
      ('salon', '客席',     'ワゴン・カラー剤の棚',      'weekly',       0, ''),

      -- ペット
      ('pet',   'トリミング', 'トリミング台',            'daily',        0, 'お客様ごとに消毒'),
      ('pet',   'トリミング', 'バリカン刃・ハサミ',      'daily',        0, '刃の消毒と注油'),
      ('pet',   '水まわり',   'シャンプー室・浴槽',      'daily',        6, '排水の毛。半年に1回は配管の洗浄を'),
      ('pet',   '預かり',     'ケージ・サークル',        'daily',        0, 'お預かりごとに消毒'),
      ('pet',   '預かり',     'ホテルのお部屋',          'daily',        0, ''),
      ('pet',   '空調',       '脱臭機・空気清浄機',      'weekly',      12, 'フィルター。年1回は業者さんへ'),
      ('pet',   '水まわり',   '洗濯機（槽の洗浄）',      'monthly',     12, ''),
      ('pet',   '衛生',       '床の消毒',                'daily',        0, '次亜塩素酸など、決めたもので'),
      ('pet',   '衛生',       '汚物・排泄物の処理',      'daily',        0, 'その日のうちに持ち出す'),
      ('pet',   '送迎',       '送迎車（車内）',          'daily',       12, '毛とにおい。年1回はクリーニングを')
    ) as v(k, area, name, cycle, pro, how)
    where v.k = '*' or v.k = v_kind
  loop
    insert into public.clean_spot(
      tenant_id, store_id, name, area, cycle, pro_months, how, sort_no)
    values (st.tenant_id, p_store, r.name, r.area, r.cycle, r.pro,
            nullif(r.how, ''), 100 + n)
    on conflict (store_id, name) do nothing;
    n := n + 1;
  end loop;

  return n;
end;
$$;

revoke all on function app.clean_seed_core(uuid, text) from anon, authenticated;


create or replace function public.clean_seed(p_store uuid, p_kind text default null)
returns integer
language plpgsql security definer set search_path = public, app
as $$
begin
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  return app.clean_seed_core(p_store, p_kind);
end;
$$;


-- ============================================================================
--  10. 記録をふりかえる
-- ============================================================================
create or replace function public.clean_history(
  p_store uuid, p_from date default null, p_to date default null, p_limit integer default 200)
returns table (
  id uuid, business_date date, ymd text, name text, area text,
  kind text, kind_label text, note text, who text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  return query
    select l.id, l.business_date,
           to_char(l.business_date, 'MM/DD') || '（' || app.dow_ja(l.business_date) || '）',
           coalesce(s.name, l.spot_name), s.area,
           l.kind,
           case l.kind when 'pro' then '業者さん' else '自分たち' end,
           l.note, st.name
      from public.clean_log l
      left join public.clean_spot s on s.id = l.spot_id
      left join public.staff st on st.id = l.created_by
     where l.store_id = p_store
       and (p_from is null or l.business_date >= p_from)
       and (p_to is null or l.business_date <= p_to)
     order by l.business_date desc, l.created_at desc
     limit coalesce(p_limit, 200);
end;
$$;


-- ============================================================================
--  11. 行の見せ方（RLS）と権限
-- ============================================================================
alter table public.clean_spot enable row level security;
alter table public.clean_log  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['clean_spot','clean_log'] loop
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format(
      'create policy p_%1$s on public.%1$s for all
         using (tenant_id = app.my_tenant() and app.can_store(store_id))
         with check (tenant_id = app.my_tenant() and app.can_store(store_id))', t);
  end loop;
end $$;

grant select, insert, update, delete on
  public.clean_spot, public.clean_log to authenticated;

revoke all on function
  public.clean_today(uuid, date),
  public.clean_pro_due(uuid),
  public.clean_alert_count(uuid),
  public.clean_done(uuid, uuid, text, date, text, text),
  public.clean_undo(uuid, uuid, date, text),
  public.clean_extra_remove(uuid),
  public.clean_spot_list(uuid, boolean),
  public.clean_spot_save(uuid, uuid, text, text, text, integer, integer,
                         integer, date, text, text, integer, boolean),
  public.clean_sheet(uuid, date, integer),
  public.clean_seed(uuid, text),
  public.clean_history(uuid, date, date, integer)
from public, anon;

grant execute on function
  public.clean_today(uuid, date),
  public.clean_pro_due(uuid),
  public.clean_alert_count(uuid),
  public.clean_done(uuid, uuid, text, date, text, text),
  public.clean_undo(uuid, uuid, date, text),
  public.clean_extra_remove(uuid),
  public.clean_spot_list(uuid, boolean),
  public.clean_spot_save(uuid, uuid, text, text, text, integer, integer,
                         integer, date, text, text, integer, boolean),
  public.clean_sheet(uuid, date, integer),
  public.clean_seed(uuid, text),
  public.clean_history(uuid, date, date, integer)
to authenticated;

notify pgrst, 'reload schema';


-- ============================================================================
--  確認用（店舗IDを入れかえてお使いください）
--
--   -- ひな形を入れる（業種は、お店の industry から決まります）
--   select app.clean_seed_core('店舗ID');
--
--   -- 入ったかどうか
--   select area, name, cycle, pro_months from public.clean_spot
--    where store_id = '店舗ID' order by sort_no;
--
--  ※ clean_today などは「ログインした方」が前提の関数です。
--    SQL Editor から呼ぶと 0件 になりますが、画面からはきちんと出ます。
-- ============================================================================

-- ############################################################################
-- #
-- #   8. デモのデータ   （024_demo.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通 / デモのデータをひととおり入れる
--  024_demo.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜023 と、業種のSQLを先に実行しておいてください）
--
--  これまでのデモデータは、売上や予約といった「数字」が中心でした。
--  ここでは、商談でひととおり動かしてお見せできるように、
--  次のものにも中身を入れます。
--
--   ・清掃・やること … 場所のひな形、この2週間の実施記録、きょうのやり残し、
--                       きょうだけの追加、業者さんのクリーニングの前回日
--                       （期限がきているものと、まだ先のものを混ぜます）
--   ・在庫・発注　　 … 商品のひな形、この2週間の出し入れ、
--                       発注書3枚（下書き・発注ずみ・納品ずみ）
--   ・届出・許可証　 … 業種ごとのひな形、期限を散らします
--                       （すぐ・もうすぐ・まだ先）
--   ・シフト希望　　 … 受付中の期間をひとつ
--
--  ★ 入れ直しても増えません。すでにあるものは、そのままにします。
--  ★ お客様の実データが入っている本番のお店では、実行しないでください。
--
--  使い方（店舗IDを入れかえてください）
--     select app.demo_fill_core('店舗ID');      -- 1店だけ
--     select app.demo_fill_all();               -- 登録ぜんぶのお店
--
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 清掃・やること
-- ============================================================================
create or replace function app.demo_fill_clean(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare
  st public.store; me uuid; d0 date; r record; i integer; n integer := 0;
  v_pro date; k integer;
begin
  if to_regclass('public.clean_spot') is null then return 0; end if;
  select * into st from public.store where id = p_store;
  if not found then return 0; end if;
  d0 := current_date;

  select id into me from public.staff
   where tenant_id = st.tenant_id and is_active
   order by case role when 'owner' then 0 when 'manager' then 1 else 2 end
   limit 1;

  --  場所のひな形（まだ無ければ）
  if not exists (select 1 from public.clean_spot where store_id = p_store) then
    perform app.clean_seed_core(p_store, st.industry);
  end if;

  --  この2週間の実施記録
  k := 0;
  for r in
    select * from public.clean_spot
     where store_id = p_store and is_active order by sort_no, name
  loop
    k := k + 1;

    --  ひとつだけ、わざと「しばらく手が回っていない」ところを作ります
    --  （9日前でとまっているので、画面では赤く出ます）
    if k = 3 then
      insert into public.clean_log(
        tenant_id, store_id, spot_id, business_date, kind, created_by)
      values (st.tenant_id, p_store, r.id, d0 - 9, 'self', me)
      on conflict do nothing;
      n := n + 1;
      continue;
    end if;

    if r.cycle = 'daily' then
      for i in 1..14 loop
        insert into public.clean_log(
          tenant_id, store_id, spot_id, business_date, kind, created_by)
        values (st.tenant_id, p_store, r.id, d0 - i, 'self', me)
        on conflict do nothing;
        n := n + 1;
      end loop;
    elsif r.cycle = 'weekly' then
      foreach i in array array[3, 10] loop
        insert into public.clean_log(
          tenant_id, store_id, spot_id, business_date, kind, created_by)
        values (st.tenant_id, p_store, r.id, d0 - i, 'self', me)
        on conflict do nothing;
        n := n + 1;
      end loop;
    elsif r.cycle = 'monthly' then
      insert into public.clean_log(
        tenant_id, store_id, spot_id, business_date, kind, created_by)
      values (st.tenant_id, p_store, r.id, d0 - 12, 'self', me)
      on conflict do nothing;
      n := n + 1;
    end if;

    --  きょうのぶんは、はじめの3か所だけ「すんだ」ことにします
    if k <= 3 and r.cycle = 'daily' then
      insert into public.clean_log(
        tenant_id, store_id, spot_id, business_date, kind, created_by)
      values (st.tenant_id, p_store, r.id, d0, 'self', me)
      on conflict do nothing;
    end if;
  end loop;

  --  業者さんのクリーニング。期限がきたものと、まだ先のものを混ぜます
  k := 0;
  for r in
    select * from public.clean_spot
     where store_id = p_store and is_active and pro_months > 0
     order by sort_no, name
  loop
    k := k + 1;
    if exists (select 1 from public.clean_log
                where spot_id = r.id and kind = 'pro') then
      continue;
    end if;
    --  3つに1つは、期限ごえ。ほかはまだ先。
    if k % 3 = 1 then
      v_pro := d0 - (r.pro_months * 30 + 25);
    else
      v_pro := d0 - (r.pro_months * 30 / 3);
    end if;
    insert into public.clean_log(
      tenant_id, store_id, spot_id, business_date, kind, note, created_by)
    values (st.tenant_id, p_store, r.id, v_pro, 'pro',
            'デモ用の記録です', me);
    n := n + 1;
  end loop;

  --  きょうだけの追加ぶん
  if not exists (select 1 from public.clean_log
                  where store_id = p_store and business_date = d0
                    and spot_id is null) then
    insert into public.clean_log(
      tenant_id, store_id, spot_name, business_date, kind, note, created_by)
    values (st.tenant_id, p_store, '看板の電球を替える', d0, 'self',
            '脚立は事務所です', me);
    n := n + 1;
  end if;

  return n;
end;
$$;


-- ============================================================================
--  2. 在庫・発注
-- ============================================================================
create or replace function app.demo_fill_stock(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare
  st public.store; me uuid; d0 date; r record; i integer; n integer := 0;
  o1 uuid; o2 uuid; o3 uuid; k integer; v_kind text;
begin
  if to_regclass('public.stock_product') is null then return 0; end if;
  select * into st from public.store where id = p_store;
  if not found then return 0; end if;
  --  この在庫は、ナイト・キャストの画面のものです。
  --  フード・サロン・ペットには、それぞれ専用の在庫があります。
  if coalesce(st.industry, '') not in ('night', 'cast') then return 0; end if;
  d0 := current_date;

  select id into me from public.staff
   where tenant_id = st.tenant_id and is_active
   order by case role when 'owner' then 0 when 'manager' then 1 else 2 end
   limit 1;

  --  商品のひな形（まだ無ければ）
  if not exists (select 1 from public.stock_product where store_id = p_store) then
    v_kind := st.industry;
    perform app.stock_seed_product_core(p_store, v_kind);
  end if;

  --  この2週間の出し入れ（すでに動いていれば、何もしません）
  if not exists (select 1 from public.stock_move where store_id = p_store) then
    k := 0;
    for r in
      select * from public.stock_product
       where store_id = p_store and is_active order by sort_no, name
    loop
      k := k + 1;
      for i in 1..7 loop
        insert into public.stock_move(
          tenant_id, store_id, product_id, business_date, kind, qty,
          unit_price, note, created_by)
        values (st.tenant_id, p_store, r.id, d0 - i * 2, 'use',
                -1 * greatest(round(r.reorder_qty / 6.0), 1),
                r.cost, null, me);
        n := n + 1;
      end loop;
      --  3つに1つは、途中で仕入れています
      if k % 3 = 0 then
        insert into public.stock_move(
          tenant_id, store_id, product_id, business_date, kind, qty,
          unit_price, note, created_by)
        values (st.tenant_id, p_store, r.id, d0 - 6, 'in',
                greatest(r.reorder_qty, 1), r.cost, 'デモ用の仕入れ', me);
        n := n + 1;
      end if;
    end loop;
  end if;

  --  発注書。下書き・発注ずみ・納品ずみ を1枚ずつ
  if not exists (select 1 from public.stock_order where store_id = p_store) then

    --  ① 納品ずみ（1週間前に頼んで、届いています）
    insert into public.stock_order(
      tenant_id, store_id, supplier, order_date, deliver_date, status,
      created_by, sent_by, sent_at, recv_by, recv_at)
    values (st.tenant_id, p_store,
            (select supplier from public.stock_product
              where store_id = p_store and supplier is not null limit 1),
            d0 - 9, d0 - 7, 'received', me, me, now() - interval '9 days',
            me, now() - interval '7 days')
    returning id into o1;

    insert into public.stock_order_line(
      order_id, product_id, name, unit, qty, recv_qty, unit_price, sort_no)
    select o1, p.id, p.name, p.unit, greatest(p.reorder_qty, 1),
           greatest(p.reorder_qty, 1), p.cost, p.sort_no
      from public.stock_product p
     where p.store_id = p_store and p.is_active
     order by p.sort_no limit 3;

    --  ② 発注ずみ（おととい頼んで、まだ届いていません）
    insert into public.stock_order(
      tenant_id, store_id, supplier, order_date, deliver_date, status,
      created_by, sent_by, sent_at)
    values (st.tenant_id, p_store, '酒販店', d0 - 2, d0 + 1, 'sent',
            me, me, now() - interval '2 days')
    returning id into o2;

    insert into public.stock_order_line(
      order_id, product_id, name, unit, qty, unit_price, sort_no)
    select o2, p.id, p.name, p.unit, greatest(p.reorder_qty, 1), p.cost, p.sort_no
      from public.stock_product p
     where p.store_id = p_store and p.is_active
     order by p.sort_no offset 3 limit 2;

    --  ③ 下書き（きょう作ったところ）
    insert into public.stock_order(
      tenant_id, store_id, supplier, order_date, deliver_date, status, created_by)
    values (st.tenant_id, p_store, 'リネン', d0, d0 + 2, 'draft', me)
    returning id into o3;

    insert into public.stock_order_line(
      order_id, product_id, name, unit, qty, unit_price, note, sort_no)
    select o3, p.id, p.name, p.unit, greatest(p.reorder_qty, 1), p.cost,
           '残り ' || app.qty_text(p.stock) || p.unit, p.sort_no
      from public.stock_product p
     where p.store_id = p_store and p.is_active
       and p.reorder_point > 0 and p.stock <= p.reorder_point
     order by p.sort_no limit 3;

    --  下書きが空っぽになってしまったら、1品だけ入れておきます
    if not exists (select 1 from public.stock_order_line where order_id = o3) then
      insert into public.stock_order_line(
        order_id, product_id, name, unit, qty, unit_price, sort_no)
      select o3, p.id, p.name, p.unit, greatest(p.reorder_qty, 1), p.cost, p.sort_no
        from public.stock_product p
       where p.store_id = p_store and p.is_active
       order by p.sort_no limit 1;
    end if;

    n := n + 3;
  end if;

  return n;
end;
$$;


-- ============================================================================
--  3. 届出・許可証
-- ============================================================================
create or replace function app.demo_fill_doc(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; d0 date; r record; k integer := 0; n integer := 0;
begin
  if to_regclass('public.store_doc') is null then return 0; end if;
  select * into st from public.store where id = p_store;
  if not found then return 0; end if;
  d0 := current_date;

  if not exists (select 1 from public.store_doc where store_id = p_store) then
    perform app.store_doc_seed_core(p_store, st.industry);
  end if;

  --  期限を散らします（もう切れている／もうすぐ／まだ先）
  for r in
    select * from public.store_doc
     where store_id = p_store and is_active and expires_on is null
     order by sort_no, name
  loop
    k := k + 1;
    if k = 1 then
      update public.store_doc
         set issued_on = d0 - 1100, expires_on = d0 - 12      -- 切れています
       where id = r.id;
    elsif k = 2 then
      update public.store_doc
         set issued_on = d0 - 700, expires_on = d0 + 38       -- もうすぐ
       where id = r.id;
    elsif k = 3 then
      update public.store_doc
         set issued_on = d0 - 400, expires_on = d0 + 210
       where id = r.id;
    elsif k <= 6 then
      update public.store_doc
         set issued_on = d0 - 300 - k * 20, expires_on = d0 + 300 + k * 30
       where id = r.id;
    else
      update public.store_doc set issued_on = d0 - 260 where id = r.id;
    end if;
    n := n + 1;
  end loop;

  return n;
end;
$$;


-- ============================================================================
--  4. シフト希望（受付中の期間をひとつ）
-- ============================================================================
create or replace function app.demo_fill_shift(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; d0 date; f date; t date; p uuid;
begin
  if to_regclass('public.shift_period') is null then return 0; end if;
  select * into st from public.store where id = p_store;
  if not found then return 0; end if;
  d0 := current_date;

  if to_regclass('public.shift_slot') is not null
     and not exists (select 1 from public.shift_slot where store_id = p_store) then
    perform app.shift_slot_seed_core(p_store);
  end if;

  --  つぎの半月を、受付中で作ります
  if extract(day from d0)::integer <= 15 then
    f := date_trunc('month', d0)::date + 15;
    t := (date_trunc('month', d0) + interval '1 month - 1 day')::date;
  else
    f := (date_trunc('month', d0) + interval '1 month')::date;
    t := f + 14;
  end if;

  if exists (select 1 from public.shift_period
              where store_id = p_store and period_from = f and period_to = t) then
    return 0;
  end if;

  insert into public.shift_period(
    tenant_id, store_id, kind, period_from, period_to, deadline_at, status, note)
  values (st.tenant_id, p_store, 'half', f, t,
          (f - 5)::timestamptz + interval '20 hours', 'open',
          'デモ用の受付です')
  returning id into p;

  return 1;
end;
$$;


-- ============================================================================
--  5. まとめて入れる
-- ============================================================================
create or replace function app.demo_fill_core(p_store uuid)
returns text
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; a integer; b integer; c integer; d integer;
begin
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;

  a := app.demo_fill_clean(p_store);
  b := app.demo_fill_stock(p_store);
  c := app.demo_fill_doc(p_store);
  d := app.demo_fill_shift(p_store);

  return st.name || '（' || coalesce(st.industry, '業種なし') || '）に入れました。' ||
         ' 清掃 ' || a || ' 件 ／ 在庫・発注 ' || b || ' 件 ／ 書類 ' || c ||
         ' 件 ／ シフト希望 ' || d || ' 件';
end;
$$;


create or replace function app.demo_fill_all()
returns table (store text, result text)
language plpgsql security definer set search_path = public, app
as $$
declare r record;
begin
  for r in select id, name from public.store where is_active order by name loop
    store := r.name;
    result := app.demo_fill_core(r.id);
    return next;
  end loop;
end;
$$;


revoke all on function
  app.demo_fill_clean(uuid), app.demo_fill_stock(uuid),
  app.demo_fill_doc(uuid), app.demo_fill_shift(uuid),
  app.demo_fill_core(uuid), app.demo_fill_all()
from anon, authenticated;


-- ============================================================================
--  つかいかた
--
--   -- 登録ぜんぶのお店に入れる（デモ用のプロジェクトなら、こちらでどうぞ）
--   select * from app.demo_fill_all();
--
--   -- 1店だけ
--   select app.demo_fill_core('店舗ID');
--
--  ※ 本番のお店（お客様の実データが入っているお店）では実行しないでください。
-- ============================================================================

-- ############################################################################
-- #
-- #   9. ログインの管理   （025_login.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通 / ログインの管理
--  025_login.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜024 を先に実行しておいてください）
--
--  これまで、スタッフさんにログインを渡すには、
--  Supabase の画面とSQLをさわる必要がありました。
--  お店の方には、とてもお願いできない作業です。
--
--  ここでは、店長以上の方が<画面から>
--   ・ログインを作る（招待メール／その場で仮パスワード）
--   ・パスワードを作り直す
--   ・ログインを止める
--   ・権限を変える（オーナー／店長／スタッフ／ドライバー）
--  を、ご自分のお店のスタッフにだけ行えるようにします。
--
--  ★ ほんとうの作成・停止は Edge Function「staff-login」が行います。
--    service_role の鍵はブラウザに出ません。
--    ここで作るのは、その関数が使う「確かめ役」と、画面に出す一覧です。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
-- ============================================================================


-- ============================================================================
--  1. 画面に出す一覧
--     そのお店に関わる方だけを出します。
--     オーナー・店長は全店を見られるので、法人のぜんぶが出ます。
-- ============================================================================
create or replace function public.staff_login_list(p_store uuid)
returns table (
  id uuid, name text, role text, role_label text, email text,
  has_login boolean, is_active boolean, stores integer, is_me boolean
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare me public.staff;
begin
  select * into me from app.me();
  if auth.uid() is not null then
    if me.id is null then raise exception 'ログインが必要です'; end if;
    if me.role not in ('owner','manager') then
      raise exception 'ログインの管理は、店長以上の方だけです';
    end if;
  end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を見る権限がありません';
  end if;

  return query
    select s.id, s.name, s.role,
           case s.role when 'owner' then 'オーナー' when 'manager' then '店長'
                       when 'driver' then 'ドライバー' else 'スタッフ' end,
           s.email,
           (s.auth_user_id is not null),
           s.is_active,
           (select count(*)::integer from public.staff_store ss where ss.staff_id = s.id),
           (s.id = me.id)
      from public.staff s
     where s.tenant_id = coalesce(me.tenant_id, app.my_tenant())
       and (s.role in ('owner','manager')
            or exists (select 1 from public.staff_store ss
                        where ss.staff_id = s.id and ss.store_id = p_store))
     order by case s.role when 'owner' then 0 when 'manager' then 1
                          when 'staff' then 2 else 3 end,
              s.is_active desc, s.name;
end;
$$;


-- ============================================================================
--  2. 確かめ役（Edge Function が、呼んだ方の鍵で呼びます）
--
--     店長以上でなければ、ここで止まります。
--     通れば、そのスタッフの情報を返します。
-- ============================================================================
create or replace function public.staff_login_check(p_staff uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app
as $$
declare me public.staff; s public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception 'ログインの管理は、店長以上の方だけです';
  end if;

  select * into s from public.staff where id = p_staff;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  if s.tenant_id <> me.tenant_id then
    raise exception 'ほかの法人の方は、あつかえません';
  end if;

  return jsonb_build_object(
    'staff_id',  s.id,
    'tenant_id', s.tenant_id,
    'name',      s.name,
    'email',     s.email,
    'role',      s.role,
    'auth_user_id', s.auth_user_id,
    'me_id',     me.id,
    'me_role',   me.role
  );
end;
$$;


-- ============================================================================
--  3. Edge Function（service_role）だけが使うもの
-- ============================================================================

--  メールアドレスから、ログインの持ち主をさがします
create or replace function app.auth_user_by_email(p_email text)
returns uuid
language sql stable security definer set search_path = public, auth
as $$
  select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1;
$$;


--  スタッフと、ログインをむすびます
create or replace function app.staff_login_link(
  p_staff uuid, p_user uuid, p_email text)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare s public.staff;
begin
  --  ほかのスタッフに、同じログインが付いていたら外します
  update public.staff set auth_user_id = null
   where auth_user_id = p_user and id <> p_staff;

  update public.staff
     set auth_user_id = p_user,
         email = coalesce(nullif(btrim(coalesce(p_email, '')), ''), email),
         is_active = true
   where id = p_staff
  returning * into s;

  if not found then raise exception 'そのスタッフが見つかりません'; end if;

  --  スタッフ・ドライバーは、所属店舗が無いと何も見えません。
  --  まだどこにも所属していなければ、法人のぜんぶのお店に入れておきます。
  if s.role in ('staff','driver')
     and not exists (select 1 from public.staff_store ss where ss.staff_id = s.id) then
    insert into public.staff_store(staff_id, store_id)
    select s.id, st.id from public.store st where st.tenant_id = s.tenant_id
    on conflict do nothing;
  end if;

  return s;
end;
$$;


--  ログインを外します（名簿は残します）
create or replace function app.staff_login_unlink(p_staff uuid)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare s public.staff;
begin
  update public.staff set auth_user_id = null where id = p_staff returning * into s;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  return s;
end;
$$;


-- ----------------------------------------------------------------------------
--  Edge Function からは public の名前でしか呼べないので、うすい入口を作ります。
--  service_role（関数の中）だけが使えます。ブラウザからは呼べません。
-- ----------------------------------------------------------------------------
create or replace function public.sr_auth_user_by_email(p_email text)
returns uuid
language sql stable security definer set search_path = public, app
as $$ select app.auth_user_by_email(p_email); $$;

create or replace function public.sr_staff_login_link(
  p_staff uuid, p_user uuid, p_email text)
returns public.staff
language sql security definer set search_path = public, app
as $$ select app.staff_login_link(p_staff, p_user, p_email); $$;

create or replace function public.sr_staff_login_unlink(p_staff uuid)
returns public.staff
language sql security definer set search_path = public, app
as $$ select app.staff_login_unlink(p_staff); $$;

revoke all on function
  public.sr_auth_user_by_email(text),
  public.sr_staff_login_link(uuid, uuid, text),
  public.sr_staff_login_unlink(uuid)
from public, anon, authenticated;

grant execute on function
  public.sr_auth_user_by_email(text),
  public.sr_staff_login_link(uuid, uuid, text),
  public.sr_staff_login_unlink(uuid)
to service_role;


-- ============================================================================
--  4. 権限を変える（画面から・店長以上だけ）
--
--   ・ご自分の権限は変えられません（自分で自分を締め出さないように）
--   ・オーナーが1人もいなくなる変更は、できません
-- ============================================================================
create or replace function public.staff_role_set(p_staff uuid, p_role text)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; s public.staff; n integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception '権限を変えられるのは、店長以上の方だけです';
  end if;
  if p_role not in ('owner','manager','staff','driver') then
    raise exception 'その権限は選べません';
  end if;

  select * into s from public.staff where id = p_staff;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  if s.tenant_id <> me.tenant_id then
    raise exception 'ほかの法人の方は、あつかえません';
  end if;
  if s.id = me.id then
    raise exception 'ご自分の権限は、この画面からは変えられません';
  end if;
  if me.role = 'manager' and p_role = 'owner' then
    raise exception 'オーナーにできるのは、オーナーの方だけです';
  end if;

  if s.role = 'owner' and p_role <> 'owner' then
    select count(*) into n from public.staff
     where tenant_id = s.tenant_id and role = 'owner' and is_active and id <> s.id;
    if n = 0 then
      raise exception 'オーナーが1人もいなくなってしまいます。先に別の方をオーナーにしてください';
    end if;
  end if;

  update public.staff set role = p_role where id = p_staff returning * into s;

  --  スタッフ・ドライバーになったら、所属店舗が要ります
  if s.role in ('staff','driver')
     and not exists (select 1 from public.staff_store ss where ss.staff_id = s.id) then
    insert into public.staff_store(staff_id, store_id)
    select s.id, st.id from public.store st where st.tenant_id = s.tenant_id
    on conflict do nothing;
  end if;

  return s;
end;
$$;


-- ============================================================================
--  5. 名簿に足す（ログインはまだ付けません）
-- ============================================================================
create or replace function public.staff_add(
  p_store uuid, p_name text, p_role text default 'staff', p_email text default null)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; s public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception 'スタッフを足せるのは、店長以上の方だけです';
  end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if nullif(btrim(coalesce(p_name, '')), '') is null then
    raise exception 'お名前を入れてください';
  end if;
  if p_role not in ('owner','manager','staff','driver') then
    raise exception 'その権限は選べません';
  end if;
  if me.role = 'manager' and p_role = 'owner' then
    raise exception 'オーナーにできるのは、オーナーの方だけです';
  end if;

  select * into st from public.store where id = p_store;

  insert into public.staff(tenant_id, name, role, email, is_active)
  values (st.tenant_id, btrim(p_name), p_role,
          nullif(btrim(coalesce(p_email, '')), ''), true)
  returning * into s;

  if s.role in ('staff','driver') then
    insert into public.staff_store(staff_id, store_id) values (s.id, p_store)
    on conflict do nothing;
  end if;

  return s;
end;
$$;


--  名簿から外す（記録は残ります）
create or replace function public.staff_stop(p_staff uuid)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; s public.staff; n integer;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception 'この操作は、店長以上の方だけです';
  end if;
  select * into s from public.staff where id = p_staff;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  if s.tenant_id <> me.tenant_id then
    raise exception 'ほかの法人の方は、あつかえません';
  end if;
  if s.id = me.id then
    raise exception 'ご自分は、この画面からは止められません';
  end if;
  if s.role = 'owner' then
    select count(*) into n from public.staff
     where tenant_id = s.tenant_id and role = 'owner' and is_active and id <> s.id;
    if n = 0 then
      raise exception 'オーナーが1人もいなくなってしまいます';
    end if;
  end if;

  update public.staff set is_active = false where id = p_staff returning * into s;
  return s;
end;
$$;


create or replace function public.staff_restart(p_staff uuid)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; s public.staff;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if me.role not in ('owner','manager') then
    raise exception 'この操作は、店長以上の方だけです';
  end if;
  select * into s from public.staff where id = p_staff;
  if not found then raise exception 'そのスタッフが見つかりません'; end if;
  if s.tenant_id <> me.tenant_id then
    raise exception 'ほかの法人の方は、あつかえません';
  end if;
  update public.staff set is_active = true where id = p_staff returning * into s;
  return s;
end;
$$;


-- ============================================================================
--  6. 権限
-- ============================================================================
revoke all on function
  app.auth_user_by_email(text),
  app.staff_login_link(uuid, uuid, text),
  app.staff_login_unlink(uuid)
from public, anon, authenticated;

revoke all on function
  public.staff_login_list(uuid),
  public.staff_login_check(uuid),
  public.staff_role_set(uuid, text),
  public.staff_add(uuid, text, text, text),
  public.staff_stop(uuid),
  public.staff_restart(uuid)
from public, anon;

grant execute on function
  public.staff_login_list(uuid),
  public.staff_login_check(uuid),
  public.staff_role_set(uuid, text),
  public.staff_add(uuid, text, text, text),
  public.staff_stop(uuid),
  public.staff_restart(uuid)
to authenticated;

notify pgrst, 'reload schema';


-- ============================================================================
--  確認用
--   select * from public.staff_login_list('店舗ID');
-- ============================================================================


-- ############################################################################
-- #
-- #   11. 日報のなおし   （026_naoshi.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ / なおし
--  026_naoshi.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--
--  なおすこと
--   ナイトだんどりで「AIで下書き」や日報の画面をひらいたときに
--     column v.guests does not exist
--   と出ていました。
--
--   お客様の人数が入っている列の名前が、伝票では head_count なのに、
--   下書きを作るところだけ guests と書いてありました。私の書きまちがいです。
--   数字がずれていたのではなく、はじめから取り出せていませんでした。
--
--  何度実行しても壊れません。
--  株式会社スリーピース / AI伴走LABO
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
    'guests', (select coalesce(sum(v.head_count), 0) from public.night_visit v
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

notify pgrst, 'reload schema';

-- ============================================================================
--  確認用（店舗IDを入れかえてお使いください）
--   select public.night_report_input('店舗ID');
--   → エラーが出なければ、なおっています。
-- ============================================================================


-- ############################################################################
-- #
-- #   12. 使ってみての直し   （027_kaizen.sql）
-- #
-- ############################################################################

-- ============================================================================
--  だんどりシリーズ 共通 / 027 使ってみての直し
--
--  貼る場所： Supabase → SQL Editor（新しいクエリ）に、まるごと貼って RUN
--  貼る順番： 026 のあと
--
--  この1本ですること
--   1. 日報に「その日のひとこと」の欄をつくります
--      → AIは、この一言と、データベースの数字をもとに下書きを書きます
--   2. 席の空き（フード）が、実際に開いている卓もふくめて出るようにします
--   3. ペットのお部屋を「あとで決める」に戻せるようにします
--   4. デモに「AIの下書きから作った日報」の見本を入れます
--
--  ★ 数字はこれまでどおり、すべてデータベース側で確定させます。
--    AIは文章にするだけで、金額や件数を作ることはありません。
-- ============================================================================


-- ============================================================================
--  1. 日報の「その日のひとこと」
--
--   これまで、AIはデータベースの数字だけを見て書いていました。
--   ここに一行だけ書いていただくと、その日らしい下書きになります。
--     例）「雨で出足が遅かったけど、20時からは満席」
-- ============================================================================

alter table public.daily_report
  add column if not exists memo text not null default '';

comment on column public.daily_report.memo is
  'その日のひとこと。AIの下書きの材料になります（人が書く欄）';


--  ひとことだけを、さっと保存します（本文はさわりません）
create or replace function public.report_memo_set(
  p_store uuid, p_date date, p_memo text)
returns public.daily_report
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; r public.daily_report;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;

  select * into st from public.store where id = p_store;

  insert into public.daily_report(
    tenant_id, store_id, business_date, body, memo, source, status, updated_by)
  values (st.tenant_id, p_store, p_date, '', coalesce(p_memo, ''),
          'manual', 'draft', me.id)
  on conflict (store_id, business_date) do update
    set memo = coalesce(p_memo, ''),
        updated_by = me.id
  returning * into r;
  return r;
end;
$$;


--  本文の保存。ひとことは、渡されなければそのまま残します。
--   ★ 古いほう（ひとことなし）は、まぎらわしいので消します。
drop function if exists public.report_save(uuid, date, text, text, text);

create or replace function public.report_save(
  p_store uuid, p_date date, p_body text,
  p_status text default 'draft', p_source text default 'manual',
  p_memo text default null)
returns public.daily_report
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; st public.store; r public.daily_report;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  --  「fixed」と書かれることがあったので、ここで受けとめます
  if p_status = 'fixed' then p_status := 'confirmed'; end if;
  if p_status not in ('draft','confirmed') then
    raise exception 'その状態にはできません';
  end if;

  select * into st from public.store where id = p_store;

  insert into public.daily_report(
    tenant_id, store_id, business_date, body, memo, source, status,
    confirmed_by, confirmed_at, updated_by)
  values (st.tenant_id, p_store, p_date, coalesce(p_body, ''),
          coalesce(p_memo, ''), p_source, p_status,
          case when p_status = 'confirmed' then me.id end,
          case when p_status = 'confirmed' then now() end,
          me.id)
  on conflict (store_id, business_date) do update
    set body = excluded.body,
        memo = coalesce(p_memo, public.daily_report.memo),
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


--  AIに渡す「ひとこと」。Edge Function から呼びます。
create or replace function public.report_memo_get(p_store uuid, p_date date)
returns text
language plpgsql stable security definer set search_path = public, app
as $$
declare t text;
begin
  if not app.can_store(p_store) then return ''; end if;
  select memo into t from public.daily_report
   where store_id = p_store and business_date = p_date;
  return coalesce(t, '');
end;
$$;


-- ============================================================================
--  2. 席の空き（フード）
--
--   これまでは「その日のご予約が入っているか」だけを見ていました。
--   そのため、飛び込みのお客様を「卓を開ける」でご案内しても、
--   席の空きの画面は「空いています」のままでした。
--   いま開いている卓（お会計まえ）も、あわせて返します。
-- ============================================================================

drop function if exists public.food_table_board(uuid, date);

create or replace function public.food_table_board(p_store uuid, p_date date default null)
returns table (
  table_id uuid, table_name text, area_name text, seats_max integer,
  res_id uuid, start_hm text, end_hm text, guests integer,
  guest_name text, status text,
  --  ここから下が、今回ふえたぶんです
  sess_id uuid, sess_guests integer, sess_from text
)
language plpgsql stable security definer set search_path = public, app
as $$
#variable_conflict use_column
declare st public.store; d date;
begin
  if not app.can_store(p_store) then raise exception 'この店舗を見る権限がありません'; end if;
  select * into st from public.store where id = p_store;
  d := coalesce(p_date, app.business_date(now(), st.day_cutoff));

  return query
  with sess as (
    select s.table_id, s.id as sid, s.guests as sguests, s.opened_at
      from public.food_session s
     where s.store_id = p_store and s.status = 'open'
  )
  select t.id, t.name, a.name, t.seats_max,
         r.id,
         to_char(r.start_at at time zone 'Asia/Tokyo', 'HH24:MI'),
         to_char(r.end_at   at time zone 'Asia/Tokyo', 'HH24:MI'),
         r.guests, coalesce(c.name, r.guest_name), r.status,
         sess.sid, sess.sguests,
         to_char(sess.opened_at at time zone 'Asia/Tokyo', 'HH24:MI')
    from public.food_table t
    left join public.food_area a on a.id = t.area_id
    left join public.food_reservation_table rt on rt.table_id = t.id
    left join public.food_reservation r
           on r.id = rt.reservation_id and r.business_date = d
          and r.status not in ('cancel','noshow')
    left join public.food_customer c on c.id = r.customer_id
    left join sess on sess.table_id = t.id
   where t.store_id = p_store and t.is_active
   order by a.sort_no nulls last, t.sort_no, t.name, r.start_at;
end;
$$;

grant execute on function public.food_table_board(uuid, date) to authenticated;


--  卓をタップしたら、その場でお通しできるようにします。
--   ・ご予約を渡せば、その卓にひもづけて「ご来店」にします
--   ・渡さなければ、飛び込みのお客様として開けます
--  ※ public.food_session が無い業種（ナイトなど）では作りません（型が無いとエラーで止まるため）
do $guard$
begin
  if to_regclass('public.food_session') is null then return; end if;

  execute $fn$
create or replace function public.food_seat_take(
  p_store uuid, p_table uuid, p_guests integer default 2,
  p_reservation uuid default null)
returns public.food_session
language plpgsql security definer set search_path = public, app
as $$
declare s public.food_session;
begin
  if not app.can_store(p_store) then
    raise exception 'この店舗を操作する権限がありません';
  end if;
  if p_table is null then raise exception 'どの卓か分かりません'; end if;

  --  ご予約ぶんなら、卓のひもづけと状態も、あわせて直します
  if p_reservation is not null then
    perform public.food_res_assign(p_reservation, array[p_table]);
    perform public.food_res_status(p_reservation, 'seated');
  end if;

  s := public.food_session_open(p_store, p_table, greatest(coalesce(p_guests, 2), 1),
                                p_reservation);
  return s;
end;
$$
  $fn$;
  execute $fn$revoke all on function public.food_seat_take(uuid, uuid, integer, uuid) from public$fn$;
  execute $fn$grant execute on function public.food_seat_take(uuid, uuid, integer, uuid) to authenticated$fn$;
end
$guard$;


-- ============================================================================
--  3. ペットのお部屋を「あとで決める」に戻せるようにします
--
--   これまでは、いちど決めたお部屋を外せませんでした。
-- ============================================================================

--  ※ public.pet_stay が無い業種（ナイトなど）では作りません（型が無いとエラーで止まるため）
do $guard$
begin
  if to_regclass('public.pet_stay') is null then return; end if;

  execute $fn$
create or replace function public.pet_stay_set(
  p_stay uuid, p_from date default null, p_to date default null,
  p_room uuid default null, p_menu uuid default null, p_meal text default null,
  p_medicine text default null, p_belongings text default null,
  p_pickup timestamptz default null, p_note text default null,
  p_clear_room boolean default false)
returns public.pet_stay
language plpgsql security definer set search_path = public, app
as $$
declare s public.pet_stay; d public.pet_dog; v_nights integer; v_price integer;
begin
  select * into s from public.pet_stay where id = p_stay;
  if not found then raise exception 'お泊まりが見つかりません'; end if;
  if not app.can_store(s.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;
  if s.status = 'out' then raise exception 'お引き渡しずみのぶんは直せません'; end if;

  select * into d from public.pet_dog where id = s.dog_id;
  v_nights := case when coalesce(s.kind, 'hotel') = 'hotel'
                   then greatest((coalesce(p_to, s.to_date) - coalesce(p_from, s.from_date)), 1)
                   else (coalesce(p_to, s.to_date) - coalesce(p_from, s.from_date)) + 1 end;
  v_price := coalesce(app.pet_menu_price(coalesce(p_menu, s.menu_id), d.size), s.unit_price);

  update public.pet_stay
     set from_date  = coalesce(p_from, from_date),
         to_date    = coalesce(p_to, to_date),
         room_id    = case when p_clear_room then null
                           else coalesce(p_room, room_id) end,
         menu_id    = coalesce(p_menu, menu_id),
         nights     = v_nights,
         unit_price = v_price,
         amount     = v_price * v_nights,
         meal_plan  = coalesce(p_meal, meal_plan),
         medicine   = coalesce(p_medicine, medicine),
         belongings = coalesce(p_belongings, belongings),
         pickup_at  = coalesce(p_pickup, pickup_at),
         note       = coalesce(p_note, note)
   where id = p_stay returning * into s;
  return s;
end;
$$
  $fn$;
  execute $fn$grant execute on function public.pet_stay_set(
  uuid, date, date, uuid, uuid, text, text, text, timestamptz, text, boolean)
  to authenticated$fn$;
end
$guard$;


-- ============================================================================
--  4. 権限のわりふり
-- ============================================================================

revoke all on function public.report_memo_set(uuid, date, text) from public;
grant execute on function public.report_memo_set(uuid, date, text) to authenticated;

revoke all on function public.report_save(uuid, date, text, text, text, text) from public;
grant execute on function public.report_save(uuid, date, text, text, text, text) to authenticated;

revoke all on function public.report_memo_get(uuid, date) from public;
grant execute on function public.report_memo_get(uuid, date) to authenticated;


-- ============================================================================
--  5. デモに「AIの下書きから作った日報」の見本を入れます
--
--   営業のときに「これが、AIが書いた下書きを、店長さまが直して確定したものです」
--   と、そのままお見せいただけます。
-- ============================================================================

create or replace function app.demo_fill_report(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; d date; n integer := 0; v_kind text;
        v_memo text; v_body text;
begin
  select * into st from public.store where id = p_store;
  if not found then return 0; end if;
  v_kind := coalesce(st.industry, 'night');
  d := app.business_date(now(), st.day_cutoff) - 1;

  if v_kind = 'night' then
    v_memo := '雨で出足が遅め。21時から満席。新規のお客様が3組。';
    v_body :=
      '【きのうの営業】' || E'\n' ||
      '雨のせいか、18時から20時までは静かな立ち上がりでした。' ||
      '21時をすぎたあたりから席がうまり、そのまま最後まで動きがありました。' || E'\n\n' ||
      '新しいお客様が3組。うち1組はご紹介でした。' ||
      'ボトルを入れてくださった方がいらっしゃるので、次のご来店のご案内を忘れないようにします。' || E'\n\n' ||
      '【気をつけたいこと】' || E'\n' ||
      '・雨の日は、はじめの2時間の人の置き方を考えなおす' || E'\n' ||
      '・ご紹介でいらした方に、お礼のご連絡を入れる';
  elsif v_kind = 'cast' then
    v_memo := '土曜。夜のご指名が多め。車が1台こみ合って、10分ほどお待たせ。';
    v_body :=
      '【きのうの動き】' || E'\n' ||
      '土曜日で、20時から24時に集中しました。ご指名でのご依頼が目立ちます。' || E'\n\n' ||
      'お送りの車が1台に重なり、10分ほどお待ちいただいた回がありました。' ||
      '同じ時間帯にご依頼が重なりやすいので、その時間だけ配車を手あつくします。' || E'\n\n' ||
      '【気をつけたいこと】' || E'\n' ||
      '・21〜23時の配車を、あらかじめ2台に' || E'\n' ||
      '・お待たせした方に、ひとことお詫びのご連絡';
  elsif v_kind = 'food' then
    v_memo := 'ランチ好調。夜は団体が1件キャンセル。日替わりが早じまい。';
    v_body :=
      '【きのうの営業】' || E'\n' ||
      'お昼は開店から満席で、日替わりが13時前になくなりました。' ||
      '数をもう少し用意しておいたほうがよさそうです。' || E'\n\n' ||
      '夜は、ご予約の団体さまが1件お取り消しになり、' ||
      '席にすこし余裕が出ました。その場でご案内できた飛び込みの方が2組。' || E'\n\n' ||
      '【気をつけたいこと】' || E'\n' ||
      '・日替わりの仕込みを、平日は少し多めに' || E'\n' ||
      '・団体のご予約は、前日にご確認のご連絡を入れる';
  elsif v_kind = 'salon' then
    v_memo := '縮毛矯正が2件。店販のトリートメントがよく出た。次回予約は3件。';
    v_body :=
      '【きのうの営業】' || E'\n' ||
      '縮毛矯正が2件入り、お時間のかかる日でした。' ||
      'そのぶん、あいだのカットのご案内が少し窮屈になりました。' || E'\n\n' ||
      '店販は、トリートメントがよく出ています。' ||
      'お仕上げのときにお話しすると、手に取っていただけることが多いです。' || E'\n\n' ||
      '次のご予約をその場でいただけたのが3件でした。' || E'\n\n' ||
      '【気をつけたいこと】' || E'\n' ||
      '・お時間のかかるメニューは、前後の組み方を見なおす' || E'\n' ||
      '・お仕上げのときのひとことを、みんなでそろえる';
  else
    v_memo := 'トリミング5頭。お泊まりの子が1頭、食べムラあり。送迎は時間どおり。';
    v_body :=
      '【きのうのようす】' || E'\n' ||
      'トリミングが5頭。大きな子が続いたので、午後は少し押しぎみでした。' || E'\n\n' ||
      'お泊まりの子が1頭、ごはんの食べムラがありました。' ||
      '量を減らして回数を増やしたところ、夕方には食べてくれています。' ||
      'お迎えのときに、飼い主さまへお伝えします。' || E'\n\n' ||
      'お送りは時間どおりに回れました。' || E'\n\n' ||
      '【気をつけたいこと】' || E'\n' ||
      '・大きな子が続く日は、あいだに余裕をとる' || E'\n' ||
      '・食べムラのあった子は、次回もようすを見る';
  end if;

  insert into public.daily_report(
    tenant_id, store_id, business_date, body, memo, source, status, confirmed_at)
  values (st.tenant_id, p_store, d, v_body, v_memo, 'ai', 'confirmed', now())
  on conflict (store_id, business_date) do update
    set body = excluded.body, memo = excluded.memo,
        source = 'ai', status = 'confirmed', confirmed_at = now();
  n := 1;

  --  もう1日ぶんは「下書きのまま」。ちがいが見えるようにしています。
  insert into public.daily_report(
    tenant_id, store_id, business_date, body, memo, source, status)
  values (st.tenant_id, p_store, d - 1,
          '（AIの下書きです。確かめて、直してから確定してください）' || E'\n\n' || v_body,
          v_memo, 'ai', 'draft')
  on conflict (store_id, business_date) do nothing;

  return n;
end;
$$;


-- ----------------------------------------------------------------------------
--  きょうのぶんを、少しだけ「進んだ状態」にします。
--   ・サロン … いちばん早いご予約を〈ご来店〉に
--   ・ペット … いちばん早いご予約を〈お預かり中〉に
--  営業のときに、「ご来店にすると、ここからカルテに飛べます」を
--  そのままお見せいただけます。
-- ----------------------------------------------------------------------------
create or replace function app.demo_fill_today(p_store uuid)
returns integer
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; b uuid; n integer := 0;
begin
  select * into st from public.store where id = p_store;
  if not found then return 0; end if;

  if st.industry = 'salon' then
    select id into b from public.salon_booking
     where store_id = p_store and business_date = current_date
       and status in ('new','confirmed')
     order by start_at limit 1;
    if b is not null then
      update public.salon_booking set status = 'seated' where id = b;
      --  カルテは、画面の「カルテ」ボタンを押したときに作ります。
      --  （SQLエディタからはログインしていない扱いのため、ここでは作れません）
      n := 1;
    end if;

  elsif st.industry = 'pet' then
    select id into b from public.pet_booking
     where store_id = p_store and business_date = current_date
       and status in ('new','confirmed') and dog_id is not null
     order by start_at limit 1;
    if b is not null then
      update public.pet_booking set status = 'here' where id = b;
      n := 1;
    end if;
  end if;

  return n;
end;
$$;

revoke all on function app.demo_fill_today(uuid) from anon, authenticated;


--  まとめて入れるほうにも、足しておきます
create or replace function app.demo_fill_core(p_store uuid)
returns text
language plpgsql security definer set search_path = public, app
as $$
declare st public.store; a integer; b integer; c integer; d integer; e integer;
begin
  select * into st from public.store where id = p_store;
  if not found then raise exception '店舗が見つかりません'; end if;

  a := app.demo_fill_clean(p_store);
  b := app.demo_fill_stock(p_store);
  c := app.demo_fill_doc(p_store);
  d := app.demo_fill_shift(p_store);
  e := app.demo_fill_report(p_store);
  perform app.demo_fill_today(p_store);

  return st.name || '（' || coalesce(st.industry, '業種なし') || '）に入れました。' ||
         ' 清掃 ' || a || ' 件 ／ 在庫・発注 ' || b || ' 件 ／ 書類 ' || c ||
         ' 件 ／ シフト希望 ' || d || ' 件 ／ 日報の見本 ' || e || ' 件';
end;
$$;

revoke all on function app.demo_fill_report(uuid) from anon, authenticated;


-- ============================================================================
--  たしかめかた
--
--   select * from app.demo_fill_all();
--   select business_date, source, status, memo from public.daily_report
--     order by business_date desc limit 10;
--   select * from public.food_table_board('店舗ID');
-- ============================================================================
