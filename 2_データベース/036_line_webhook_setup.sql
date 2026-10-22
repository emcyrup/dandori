-- ============================================================================
--  ナイトだんどり / LINE の Webhook を画面から設定できるようにする
--  036_line_webhook_setup.sql
--
--  貼り付け先： SQL Editor（001 … 035 のあと）。何度流しても壊れません。
--
--  LINE の受信（Webhook）には「チャネルシークレット」が要りますが、画面から入れる口が無く、
--  secret_set も受け付けていませんでした。ここで受け付けるようにし、設定の読み出しに
--  「シークレットが入っているか」と「法人ID（Webhook URL の ?t= に付ける値）」を足します。
-- ============================================================================
\set ON_ERROR_STOP on

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
    'has_line_secret', exists (select 1 from public.tenant_secret x
                               where x.tenant_id = me.tenant_id
                                 and x.key_name = 'line_channel_secret'),
    'has_mail_key',   exists (select 1 from public.tenant_secret x
                               where x.tenant_id = me.tenant_id
                                 and x.key_name in ('resend_api_key','sendgrid_api_key')),
    'tenant_id',      me.tenant_id,
    'can_edit',       me.role = 'owner'
  );
end;
$$;

create or replace function public.secret_set(p_key text, p_value text)
returns jsonb
language plpgsql security definer set search_path = public, app
as $$
declare me public.staff;
begin
  select * into me from app.me();
  if me.id is null or me.role <> 'owner' then
    raise exception '鍵の設定は、オーナーの権限が必要です';
  end if;
  if p_key not in ('line_channel_token','line_channel_secret','resend_api_key','sendgrid_api_key') then
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

notify pgrst, 'reload schema';
