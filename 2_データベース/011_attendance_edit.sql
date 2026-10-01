-- ============================================================================
--  ナイトだんどり / 出勤記録の修正
--  011_attendance_edit.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜006、004 を先に実行しておいてください）
--
--  押し忘れ・押し間違いを直せるようにします。
--  ・その日の記録は、スタッフでも直せます
--  ・過去の日を直す／記録ごと消すのは、店長以上のみ
--  何度実行しても壊れません。
-- ============================================================================


-- ----------------------------------------------------------------------------
--  1. 出勤・退勤の時刻を、手で入れ直す
--
--     p_in / p_out は「その営業日の時刻」を文字で渡します（例 '20:30'）。
--     退勤が出勤より前の時刻なら、翌日の時刻として扱います（深夜営業のため）。
--     null を渡すと、その項目は空にします。
-- ----------------------------------------------------------------------------
create or replace function public.night_attendance_set(
  p_cast uuid,
  p_date date,
  p_in   text default null,     -- '20:30' 形式。空にするなら null
  p_out  text default null,     -- '01:15' 形式。空にするなら null
  p_late integer default 0,
  p_note text default null
) returns public.night_attendance
language plpgsql security definer set search_path = public, app
as $$
declare
  me public.staff; c public.night_cast; st public.store;
  a public.night_attendance;
  ts_in timestamptz; ts_out timestamptz;
  t_in time; t_out time;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  select * into st from public.store where id = c.store_id;

  -- 今日以外を直すのは、店長以上だけ
  if p_date <> app.business_date(now(), st.day_cutoff)
     and me.role not in ('owner','manager') then
    raise exception '過去の出勤を直すには、店長以上の権限が必要です';
  end if;

  if p_in is not null and btrim(p_in) <> '' then
    t_in := p_in::time;
    -- 営業日の切り替え時刻より前の時刻＝翌日ぶん
    ts_in := ((p_date + case when t_in < st.day_cutoff then 1 else 0 end) + t_in)
             at time zone 'Asia/Tokyo';
  end if;

  if p_out is not null and btrim(p_out) <> '' then
    t_out := p_out::time;
    ts_out := ((p_date + case when t_out < st.day_cutoff then 1 else 0 end) + t_out)
              at time zone 'Asia/Tokyo';
  end if;

  if ts_in is not null and ts_out is not null and ts_out <= ts_in then
    raise exception '退勤の時刻が、出勤より前になっています';
  end if;

  insert into public.night_attendance(
    tenant_id, store_id, cast_id, business_date, clock_in, clock_out, late_minutes, note)
  values (c.tenant_id, c.store_id, c.id, p_date, ts_in, ts_out,
          greatest(coalesce(p_late,0),0), p_note)
  on conflict (cast_id, business_date) do update
    set clock_in = excluded.clock_in,
        clock_out = excluded.clock_out,
        late_minutes = excluded.late_minutes,
        note = excluded.note
  returning * into a;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (c.tenant_id, c.store_id, me.id, 'attendance_edit', 'night_attendance', a.id::text,
          jsonb_build_object('cast', c.name, 'date', p_date, 'in', p_in, 'out', p_out));

  return a;
end;
$$;


-- ----------------------------------------------------------------------------
--  2. 出勤の記録ごと消す（誤って別のキャストを押したとき）
-- ----------------------------------------------------------------------------
create or replace function public.night_attendance_delete(p_cast uuid, p_date date)
returns boolean
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; c public.night_cast; n integer;
begin
  select * into me from app.me();
  if me.role not in ('owner','manager') then
    raise exception '出勤の削除は、店長以上の権限が必要です';
  end if;

  select * into c from public.night_cast where id = p_cast;
  if not found then raise exception 'キャストが見つかりません'; end if;
  if not app.can_store(c.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  delete from public.night_attendance
   where cast_id = p_cast and business_date = p_date;
  get diagnostics n = row_count;

  if n > 0 then
    insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
    values (c.tenant_id, c.store_id, me.id, 'attendance_delete', 'night_attendance', null,
            jsonb_build_object('cast', c.name, 'date', p_date));
  end if;

  return n > 0;
end;
$$;


-- ----------------------------------------------------------------------------
--  3. 権限
-- ----------------------------------------------------------------------------
grant execute on function
  public.night_attendance_set(uuid, date, text, text, integer, text),
  public.night_attendance_delete(uuid, date)
to authenticated;


-- ============================================================================
--  確認用
--   select clock_in, clock_out from public.night_attendance_set(
--     (select id from night_cast where name='あや'), current_date, '20:30', '01:15', 0, null);
-- ============================================================================
