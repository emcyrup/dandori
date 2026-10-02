-- ============================================================================
--  ナイトだんどり / 卓の担当キャストを、あとから付ける・変える（フリーの卓の割り振り）
--  030_visit_cast.sql
--
--  フリーで入ったお客様の卓にも、ついたキャストを割り振れるようにします。
--  担当にすると、その卓で付くドリンクなどのバックと個人売上が、そのキャストに付きます
--  （指名ではないので、指名料は付きません）。
--  何度流しても壊れません。
-- ============================================================================

create or replace function public.night_set_cast(
  p_visit uuid,
  p_cast  uuid default null        -- null なら「担当なし（フリー）」に戻す
) returns public.night_visit
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff; v public.night_visit; c public.night_cast;
begin
  select * into me from app.me();
  if me.id is null then raise exception 'ログインが必要です'; end if;

  select * into v from public.night_visit where id = p_visit;
  if not found then raise exception '伝票が見つかりません'; end if;
  if v.status <> 'open' then raise exception 'この伝票は締め済みです'; end if;
  if not app.can_store(v.store_id) then raise exception 'この店舗を操作する権限がありません'; end if;

  if p_cast is not null then
    select * into c from public.night_cast where id = p_cast and store_id = v.store_id and is_active;
    if not found then raise exception 'キャストが見つかりません'; end if;
  end if;

  update public.night_visit
     set main_cast_id = p_cast, updated_at = now()
   where id = p_visit
   returning * into v;

  insert into public.audit_log(tenant_id, store_id, staff_id, action, target, target_id, detail)
  values (me.tenant_id, v.store_id, me.id, 'set_cast', 'night_visit', v.id::text,
          jsonb_build_object('table_no', v.table_no, 'cast', c.name));
  return v;
end;
$$;

grant execute on function public.night_set_cast(uuid, uuid) to authenticated;
