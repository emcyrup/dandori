-- ============================================================================
--  ナイトだんどり / 脆弱性診断（2026-10-21）で見つかった点の修正
--  035_security_fixes.sql
--
--  貼り付け先： SQL Editor（001 … 034 のあと）。何度流しても壊れません。
-- ============================================================================
\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
--  1. LINE からのシフト希望は、その法人の名簿にいる人のぶんだけ受け付ける
--     （いままでは LINE の ID だけで全法人を横断して探していたため、
--       別の法人の Webhook 経由で他法人の希望を書き換えられる余地があった）
-- ----------------------------------------------------------------------------
create or replace function public.wish_from_line(
  p_line_user_id text, p_text text, p_tenant uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare n_mine integer := 0; n_other integer := 0; t text;
begin
  if p_tenant is null then
    return jsonb_build_object('ok', false, 'reply', '申しわけありません。お店に直接ご連絡ください。');
  end if;
  -- この LINE の ID を持つ人が、この法人の店舗にいるか／ほかの法人にもいないか
  foreach t in array array['night_cast', 'cast_member', 'food_staff', 'salon_staff', 'pet_staff'] loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'select count(*) filter (where s.tenant_id = $2), count(*) filter (where s.tenant_id <> $2)
           from public.%I x join public.store s on s.id = x.store_id
          where x.line_user_id = $1 and x.is_active', t)
        into strict n_mine, n_other using p_line_user_id, p_tenant;
      exit when n_mine > 0 or n_other > 0;
    end if;
  end loop;
  if n_mine = 0 or n_other > 0 then
    return jsonb_build_object('ok', false, 'reply',
      'はじめまして。お店の名簿とつながっていないようです。' || E'\n' ||
      'お手数ですが、お店にこのメッセージをお見せください。');
  end if;
  return app.wish_from_line_core(p_line_user_id, p_text);
end;
$$;

revoke all on function public.wish_from_line(text, text) from anon, authenticated, public;
revoke all on function public.wish_from_line(text, text, uuid) from anon, authenticated, public;


-- ----------------------------------------------------------------------------
--  2. 「だれが呼んでいるか」を見分ける小さな関数
--     単一ロールモードでは、anon / authenticated / service_role の役割名が全部 public に
--     読み替えられるため、「service_role にだけ grant」は効きません。関数の中で確かめます。
-- ----------------------------------------------------------------------------
-- サーバー鍵（関数・入口）で呼ばれているか。単一ロールモードでは post-single.sql が同じ名前で上書きします
do $$
begin
  if to_regprocedure('app.is_service()') is null then
    create function app.is_service() returns boolean language sql stable as $f$
      select current_user = 'service_role'
          or coalesce((current_setting('request.jwt.claims', true))::jsonb ->> 'role', '') = 'service_role'
          or coalesce((current_setting('request.jwt.claims', true))::jsonb ->> 'svc', '') = 'true';
    $f$;
  end if;
end $$;

-- API を通らずに（psql / SQL Editor / 移行スクリプトから）実行しているか
create or replace function app.is_local() returns boolean
language sql stable
as $$ select coalesce(current_setting('request.jwt.claims', true), '') = ''; $$;

-- 画面が表に直接書いているか（RPC・トリガの中なら false）。
-- 単一ロール：関数の中は application_name が dandori_fn（rls_bypass）。役割あり：関数の中は postgres。
create or replace function app.direct_write() returns boolean
language plpgsql stable
as $$
begin
  if app.is_local() or app.is_service() then return false; end if;
  if to_regprocedure('app.rls_bypass()') is not null then
    return not app.rls_bypass();
  end if;
  return current_user in ('anon', 'authenticated');
end;
$$;
revoke all on function app.is_local(), app.direct_write() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
--  3. サーバー鍵専用のつもりだった入口に、ふたを付ける
--     （sr_*: ログインの紐づけ。line_seen / wish_from_line: LINE Webhook）
--     ふたが無いと、ログイン済みの一般スタッフが店長のログインを自分に付け替えられました。
-- ----------------------------------------------------------------------------
create or replace function public.sr_auth_user_by_email(p_email text)
returns uuid
language plpgsql stable security definer set search_path = public, app
as $$
begin
  if not app.is_service() then raise exception 'この関数はサーバーの中からだけ使えます'; end if;
  return app.auth_user_by_email(p_email);
end;
$$;

create or replace function public.sr_staff_login_link(p_staff uuid, p_user uuid, p_email text)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
begin
  if not app.is_service() then raise exception 'この関数はサーバーの中からだけ使えます'; end if;
  return app.staff_login_link(p_staff, p_user, p_email);
end;
$$;

create or replace function public.sr_staff_login_unlink(p_staff uuid)
returns public.staff
language plpgsql security definer set search_path = public, app
as $$
begin
  if not app.is_service() then raise exception 'この関数はサーバーの中からだけ使えます'; end if;
  return app.staff_login_unlink(p_staff);
end;
$$;

create or replace function public.line_seen(
  p_tenant uuid, p_line_user_id text, p_name text default null, p_pic text default null)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare r public.line_link;
begin
  if not app.is_service() then raise exception 'この関数はサーバーの中からだけ使えます'; end if;
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

-- wish_from_line(2引数) は本文が長いので、中身を app.wish_from_line_core に移し、public 側はふた付きの薄い入口にする。
-- 017-027 を流し直すと public 側がふた無しの本文に戻るので、「guard035」の印が無ければもう一度移す。
do $$
begin
  if to_regprocedure('public.wish_from_line(text,text)') is not null
     and position('guard035' in (select prosrc from pg_proc where oid = 'public.wish_from_line(text,text)'::regprocedure)) = 0 then
    drop function if exists app.wish_from_line_core(text, text);
    alter function public.wish_from_line(text, text) rename to wish_from_line_core;
    alter function public.wish_from_line_core(text, text) set schema app;
  end if;
end $$;
create or replace function public.wish_from_line(p_line_user_id text, p_text text)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
begin
  -- guard035
  if not app.is_service() then raise exception 'この関数はサーバーの中からだけ使えます'; end if;
  return app.wish_from_line_core(p_line_user_id, p_text);
end;
$$;

-- ----------------------------------------------------------------------------
--  4. LINE の結びつけ：相手は自分の法人の名簿にいる人だけ
--     （いままでは他法人の名簿の行の LINE を書き換えられ、明細・シフト通知を横取りできた）
-- ----------------------------------------------------------------------------
create or replace function public.line_link_set(p_id uuid, p_kind text, p_subject uuid)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; l public.line_link; v_tbl text; v_name text;
begin
  select * into me from app.me();
  if me.id is null or me.role not in ('owner','manager') then
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

  execute format('update %s set line_user_id = $1 where id = $2 and tenant_id = $3 returning name', v_tbl)
    into v_name using l.line_user_id, p_subject, me.tenant_id;
  if v_name is null then raise exception 'その方は見つかりません'; end if;

  update public.line_link
     set subject_kind = p_kind, subject_id = p_subject,
         linked_by = me.id, linked_at = now()
   where id = p_id;

  return jsonb_build_object('ok', true, 'name', v_name,
    'message', v_name || ' さんのLINEとして登録しました');
end;
$$;

-- ----------------------------------------------------------------------------
--  5. 業務の表に画面から直接書けるのは店長以上だけ
--     読むのは今までどおり所属店舗の人。書き込みは RPC（night_* の関数）を通るので、
--     画面の動きは変わりません。一般スタッフが PATCH で時給・給与・会計を書き換える抜け道を塞ぎます。
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'night_cast','night_menu','night_visit','night_visit_item','night_payment','night_receivable',
    'night_attendance','night_daily_close','night_payout','night_adjustment','night_payroll','night_visit_cast'
  ] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('drop policy if exists p_%1$s on public.%1$s', t);
    execute format('drop policy if exists p_%1$s_sel on public.%1$s', t);
    execute format('drop policy if exists p_%1$s_wr on public.%1$s', t);
    execute format(
      'create policy p_%1$s_sel on public.%1$s for select
         using (tenant_id = app.my_tenant() and app.can_store(store_id))', t);
    execute format(
      'create policy p_%1$s_wr on public.%1$s for all
         using (tenant_id = app.my_tenant() and app.can_store(store_id) and app.is_boss())
         with check (tenant_id = app.my_tenant() and app.can_store(store_id) and app.is_boss())', t);
  end loop;
end $$;

-- 売掛ログも同じ（親の売掛をたどる）
drop policy if exists p_night_receivable_log on public.night_receivable_log;
drop policy if exists p_night_receivable_log_sel on public.night_receivable_log;
drop policy if exists p_night_receivable_log_wr on public.night_receivable_log;
create policy p_night_receivable_log_sel on public.night_receivable_log for select
  using (exists (select 1 from public.night_receivable r
                 where r.id = receivable_id and r.tenant_id = app.my_tenant() and app.can_store(r.store_id)));
create policy p_night_receivable_log_wr on public.night_receivable_log for all
  using (app.is_boss() and exists (select 1 from public.night_receivable r
                 where r.id = receivable_id and r.tenant_id = app.my_tenant() and app.can_store(r.store_id)))
  with check (app.is_boss() and exists (select 1 from public.night_receivable r
                 where r.id = receivable_id and r.tenant_id = app.my_tenant() and app.can_store(r.store_id)));

-- ----------------------------------------------------------------------------
--  6. スタッフ名簿：画面から直接 PATCH しても、役割・ログイン・法人は変えられない
--     （店長が自分を owner にする、休眠スタッフの行に別のログインを付ける、などを防ぐ。
--       役割の変更は staff_role_set、ログインの紐づけは staff-login 関数を通る）
-- ----------------------------------------------------------------------------
create or replace function app.staff_guard_direct()
returns trigger
language plpgsql
as $$
begin
  if app.direct_write() then
    if new.role is distinct from old.role then
      raise exception '役割は「役割を変える」ボタンから変えてください';
    end if;
    if new.auth_user_id is distinct from old.auth_user_id then
      raise exception 'ログインの紐づけは「ログインを作る」から行ってください';
    end if;
    if new.tenant_id is distinct from old.tenant_id then
      raise exception '法人は変えられません';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_staff_guard_direct on public.staff;
create trigger trg_staff_guard_direct before update on public.staff
  for each row execute function app.staff_guard_direct();

-- 役割は4種類だけ（既存の行はそのまま。新しく書く値だけ確かめる）
alter table public.staff drop constraint if exists staff_role_check;
alter table public.staff add constraint staff_role_check
  check (role in ('owner','manager','staff','driver')) not valid;

-- ----------------------------------------------------------------------------
--  7. 取り込みファイル（imports バケット）は、その店舗の人だけ。上げる・消すのは店長以上
--     （置き場所は <店舗ID>/<バッチID>/ファイル名。いままでは全法人が互いに読めた）
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.objects') is not null then
    execute $q$drop policy if exists p_imports_all on storage.objects$q$;
    execute $q$drop policy if exists p_imports_read on storage.objects$q$;
    execute $q$drop policy if exists p_imports_write on storage.objects$q$;
    execute $q$
      create policy p_imports_read on storage.objects for select to authenticated
        using (bucket_id = 'imports'
               and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
               and app.can_store(((storage.foldername(name))[1])::uuid)) $q$;
    execute $q$
      create policy p_imports_write on storage.objects for all to authenticated
        using (bucket_id = 'imports' and app.is_boss()
               and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
               and app.can_store(((storage.foldername(name))[1])::uuid))
        with check (bucket_id = 'imports' and app.is_boss()
               and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
               and app.can_store(((storage.foldername(name))[1])::uuid)) $q$;
  end if;
end $$;

-- ----------------------------------------------------------------------------
--  8. 明細の印刷データ（payslip_get）は、店長以上か本人だけ
-- ----------------------------------------------------------------------------
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = 'public.payslip_get(uuid)'::regprocedure;
  if position('guard035' in src) = 0 then
    src := replace(src,
      'if not app.can_store(p.store_id) then raise exception ''この明細を見る権限がありません''; end if;',
      'if not app.can_store(p.store_id) then raise exception ''この明細を見る権限がありません''; end if;
  -- guard035: 店長以上か、本人のぶんだけ
  if not (app.is_boss() or exists (select 1 from app.my_subject() m
             where m.subject_kind = p.subject_kind and m.subject_id = p.subject_id)) then
    raise exception ''この明細を見る権限がありません'';
  end if;');
    if position('guard035' in src) = 0 then raise exception 'payslip_get のふたを付けられませんでした'; end if;
    execute format('create or replace function public.payslip_get(p_id uuid) returns jsonb
      language plpgsql stable security definer set search_path = public, app as %L', src);
  end if;
end $$;

-- ----------------------------------------------------------------------------
--  9. 伝票の再計算（night_recalc_visit）：画面から直接呼ぶなら、その店舗の人だけ
--     （トリガ・RPC・移行スクリプトからの呼び出しは今までどおり）
-- ----------------------------------------------------------------------------
do $$
begin
  if position('guard035' in (select prosrc from pg_proc where oid = 'public.night_recalc_visit(uuid)'::regprocedure)) = 0 then
    drop function if exists app.night_recalc_visit_core(uuid);
    alter function public.night_recalc_visit(uuid) rename to night_recalc_visit_core;
    alter function public.night_recalc_visit_core(uuid) set schema app;
  end if;
end $$;
create or replace function public.night_recalc_visit(p_visit uuid)
returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare v public.night_visit;
begin
  -- guard035
  if app.direct_write() then
    select * into v from public.night_visit where id = p_visit;
    if v.id is null or not app.can_store(v.store_id) then
      raise exception 'この伝票を操作する権限がありません';
    end if;
  end if;
  return app.night_recalc_visit_core(p_visit);
end;
$$;

-- ----------------------------------------------------------------------------
-- 10. 権限の点検（kengen_check）は、API からは店長以上だけ（SQL Editor からは今までどおり）
-- ----------------------------------------------------------------------------
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = 'public.kengen_check()'::regprocedure;
  if position('guard035' in src) = 0 then
    src := replace(src,
      'if auth.uid() is not null and not app.is_boss() then',
      'if not app.is_local() and not app.is_boss() then  -- guard035');
    if position('guard035' in src) = 0 then raise exception 'kengen_check のふたを付けられませんでした'; end if;
    execute format('create or replace function public.kengen_check() returns table (画面 text, 関数 text, ようす text)
      language plpgsql stable security definer set search_path = public, app as %L', src);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 11. シフト希望の送信（wish_submit）も、リンクの期限を見る（wish_open / wish_set と同じ）
-- ----------------------------------------------------------------------------
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = 'public.wish_submit(text,text)'::regprocedure;
  if position('guard035' in src) = 0 then
    src := replace(src,
      'select * into p from public.shift_period where id = w.period_id;',
      'if w.token_until is not null and w.token_until < now() then  -- guard035
    raise exception ''このリンクは期限が切れています。お店にご連絡ください'';
  end if;
  select * into p from public.shift_period where id = w.period_id;');
    if position('guard035' in src) = 0 then raise exception 'wish_submit のふたを付けられませんでした'; end if;
    execute format('create or replace function public.wish_submit(p_token text, p_note text default null) returns jsonb
      language plpgsql security definer set search_path = public, app as %L', src);
  end if;
end $$;

notify pgrst, 'reload schema';
