-- ============================================================================
--  ナイトだんどり / 商談で見せるためのデモデータ
--  007_demo_data.sql
--
--  貼り付け先： Supabase ダッシュボード → SQL Editor → New query
--               （001〜006 を先に実行しておいてください）
--
--  デモ店「三宮本店」に、直近7営業日ぶんの実績を入れます。
--  ・毎日4〜5組の来店と伝票
--  ・キャストの出勤と日払い
--  ・未回収のツケ 2件
--  ・日締め済みの履歴
--
--  これで、給与の試算も売掛一覧も締めの履歴も、中身のある状態で見せられます。
--  何度実行しても増えません（すでに入っていれば何もしません）。
--
--  ※ 本番のお客様の環境では実行しないでください。
-- ============================================================================

do $$
declare
  t_id uuid; s_id uuid;
  c_aya uuid; c_min uuid; c_rei uuid;
  cu_sato uuid; cu_tanaka uuid; cu_ito uuid; cu_watanabe uuid;
  m_set uuid; m_set90 uuid; m_ext uuid; m_nom uuid; m_bnom uuid;
  m_dou uuid; m_drk uuid; m_cham uuid; m_btl uuid; m_food uuid;
  d date; v_id uuid; i integer; n integer;
  v_total integer; v_credit integer;
  guests text[] := array['佐藤様','田中様','伊藤様','渡辺様','中村様','小林様','加藤様'];
  cast_ids uuid[];
  cast_pick uuid;
begin
  select id into t_id from public.tenant where name = 'デモ／ラウンジ彩';
  if t_id is null then
    raise notice 'デモ法人がありません。001_foundation.sql を先に実行してください。';
    return;
  end if;
  select id into s_id from public.store where tenant_id = t_id limit 1;

  -- すでに過去の実績が入っていれば何もしない
  if exists (select 1 from public.night_visit
              where store_id = s_id and status = 'closed'
                and business_date < current_date - 1) then
    raise notice 'デモの実績はすでに入っています。';
    return;
  end if;

  select id into c_aya from public.night_cast where store_id = s_id and name = 'あや';
  select id into c_min from public.night_cast where store_id = s_id and name = 'みなみ';
  select id into c_rei from public.night_cast where store_id = s_id and name = 'れい';
  cast_ids := array[c_aya, c_min, c_rei];

  -- 料金（001のデモ分。足りないものは足す）
  select id into m_set   from public.night_menu where store_id = s_id and name = 'セット（60分）';
  select id into m_ext   from public.night_menu where store_id = s_id and name = '延長（30分）';
  select id into m_nom   from public.night_menu where store_id = s_id and name = '本指名';
  select id into m_dou   from public.night_menu where store_id = s_id and name = '同伴';
  select id into m_drk   from public.night_menu where store_id = s_id and name = 'キャストドリンク';
  select id into m_btl   from public.night_menu where store_id = s_id and name = 'ボトル（焼酎）';
  select id into m_food  from public.night_menu where store_id = s_id and name = 'フルーツ盛り';

  if m_set90 is null then
    insert into public.night_menu(tenant_id, store_id, category, name, unit_price, sort_order)
    values (t_id, s_id, 'set', 'セット（90分）', 11000, 11)
    on conflict do nothing;
    select id into m_set90 from public.night_menu where store_id = s_id and name = 'セット（90分）';
  end if;
  if m_bnom is null then
    insert into public.night_menu(tenant_id, store_id, category, name, unit_price,
                                  back_amount, sort_order)
    values (t_id, s_id, 'nomination', '場内指名', 2000, 1000, 31)
    on conflict do nothing;
    select id into m_bnom from public.night_menu where store_id = s_id and name = '場内指名';
  end if;
  if m_cham is null then
    insert into public.night_menu(tenant_id, store_id, category, name, unit_price,
                                  back_rate, sort_order)
    values (t_id, s_id, 'drink', 'シャンパン（小）', 15000, 10, 51)
    on conflict do nothing;
    select id into m_cham from public.night_menu where store_id = s_id and name = 'シャンパン（小）';
  end if;

  -- お客様を足す
  select id into cu_sato   from public.night_customer where store_id = s_id and name = '佐藤様';
  select id into cu_tanaka from public.night_customer where store_id = s_id and name = '田中様';

  insert into public.night_customer(tenant_id, store_id, name, company, main_cast_id,
                                    first_visit_on, visit_count)
  values (t_id, s_id, '伊藤様', '伊藤商事', c_min, current_date - 200, 24)
  returning id into cu_ito;
  insert into public.night_customer(tenant_id, store_id, name, main_cast_id,
                                    first_visit_on, visit_count)
  values (t_id, s_id, '渡辺様', c_rei, current_date - 60, 4)
  returning id into cu_watanabe;

  -- ------------------------------------------------------------------
  --  直近7営業日ぶんの営業
  -- ------------------------------------------------------------------
  for i in 1..7 loop
    d := current_date - i;

    -- 出勤（20:00〜翌1:00 の5時間。れいは週3日）
    insert into public.night_attendance(tenant_id, store_id, cast_id, business_date, clock_in, clock_out)
    values (t_id, s_id, c_aya, d,
            (d + time '20:00') at time zone 'Asia/Tokyo',
            (d + 1 + time '01:00') at time zone 'Asia/Tokyo')
    on conflict do nothing;

    insert into public.night_attendance(tenant_id, store_id, cast_id, business_date, clock_in, clock_out)
    values (t_id, s_id, c_min, d,
            (d + time '20:30') at time zone 'Asia/Tokyo',
            (d + 1 + time '01:00') at time zone 'Asia/Tokyo')
    on conflict do nothing;

    if i % 2 = 1 then
      insert into public.night_attendance(tenant_id, store_id, cast_id, business_date, clock_in, clock_out)
      values (t_id, s_id, c_rei, d,
              (d + time '21:00') at time zone 'Asia/Tokyo',
              (d + 1 + time '00:30') at time zone 'Asia/Tokyo')
      on conflict do nothing;
    end if;

    -- 来店（4組 ＋ 週末は1組多い）
    n := case when extract(dow from d) in (5, 6) then 5 else 4 end;

    for v_id in
      select gen_random_uuid() from generate_series(1, n)
    loop
      null;  -- ループ変数だけ使うため
    end loop;

    for i in 1..n loop
      cast_pick := cast_ids[1 + ((i + extract(day from d)::integer) % 3)];

      insert into public.night_visit(
        tenant_id, store_id, business_date, table_no, customer_id, guest_name,
        head_count, main_cast_id, entered_at, status)
      values (
        t_id, s_id, d,
        (array['A-1','A-2','B-1','B-5','C-3'])[i],
        case i
          when 1 then cu_sato
          when 2 then cu_ito
          when 3 then cu_tanaka
          when 4 then cu_watanabe
          else null end,
        case when i = 5 then guests[1 + (extract(day from d)::integer % 7)] else null end,
        1 + (i % 3),
        cast_pick,
        (d + time '20:00' + (i * interval '40 minutes')) at time zone 'Asia/Tokyo',
        'open')
      returning id into v_id;

      -- セット
      insert into public.night_visit_item(
        tenant_id, store_id, visit_id, menu_id, category, name,
        unit_price, quantity, amount, cast_id, back_amount)
      select t_id, s_id, v_id, m.id, m.category, m.name,
             m.unit_price, 1 + (i % 3), m.unit_price * (1 + (i % 3)), null, 0
        from public.night_menu m where m.id = case when i % 3 = 0 then m_set90 else m_set end;

      -- 延長（半分くらい）
      if i % 2 = 0 then
        insert into public.night_visit_item(
          tenant_id, store_id, visit_id, menu_id, category, name,
          unit_price, quantity, amount, cast_id, back_amount)
        select t_id, s_id, v_id, m.id, m.category, m.name, m.unit_price, 1, m.unit_price, null, 0
          from public.night_menu m where m.id = m_ext;
      end if;

      -- 指名
      insert into public.night_visit_item(
        tenant_id, store_id, visit_id, menu_id, category, name,
        unit_price, quantity, amount, cast_id, back_amount)
      select t_id, s_id, v_id, m.id, m.category, m.name, m.unit_price, 1, m.unit_price,
             cast_pick, m.back_amount
        from public.night_menu m where m.id = case when i % 3 = 1 then m_nom else m_bnom end;

      -- 同伴（週2回くらい）
      if i = 1 and extract(dow from d) in (2, 5) then
        insert into public.night_visit_item(
          tenant_id, store_id, visit_id, menu_id, category, name,
          unit_price, quantity, amount, cast_id, back_amount)
        select t_id, s_id, v_id, m.id, m.category, m.name, m.unit_price, 1, m.unit_price,
               cast_pick, m.back_amount
          from public.night_menu m where m.id = m_dou;
      end if;

      -- キャストドリンク
      insert into public.night_visit_item(
        tenant_id, store_id, visit_id, menu_id, category, name,
        unit_price, quantity, amount, cast_id, back_amount)
      select t_id, s_id, v_id, m.id, m.category, m.name,
             m.unit_price, 1 + (i % 4), m.unit_price * (1 + (i % 4)),
             cast_pick, m.back_amount * (1 + (i % 4))
        from public.night_menu m where m.id = m_drk;

      -- ボトル・シャンパン・フード（たまに）
      if i % 4 = 0 then
        insert into public.night_visit_item(
          tenant_id, store_id, visit_id, menu_id, category, name,
          unit_price, quantity, amount, cast_id, back_amount)
        select t_id, s_id, v_id, m.id, m.category, m.name, m.unit_price, 1, m.unit_price,
               cast_pick, floor(m.unit_price * m.back_rate / 100.0)
          from public.night_menu m where m.id = m_btl;
      end if;

      if i = 2 and extract(dow from d) = 6 then
        insert into public.night_visit_item(
          tenant_id, store_id, visit_id, menu_id, category, name,
          unit_price, quantity, amount, cast_id, back_amount)
        select t_id, s_id, v_id, m.id, m.category, m.name, m.unit_price, 1, m.unit_price,
               cast_pick, floor(m.unit_price * m.back_rate / 100.0)
          from public.night_menu m where m.id = m_cham;
      end if;

      if i % 3 = 2 then
        insert into public.night_visit_item(
          tenant_id, store_id, visit_id, menu_id, category, name,
          unit_price, quantity, amount, cast_id, back_amount)
        select t_id, s_id, v_id, m.id, m.category, m.name, m.unit_price, 1, m.unit_price, null, 0
          from public.night_menu m where m.id = m_food;
      end if;

      -- 会計（1週間に2件だけツケ）
      select total into v_total from public.night_visit where id = v_id;
      v_credit := 0;
      if (i = 2 and extract(day from d)::integer % 4 = 0) then
        v_credit := v_total;
      end if;

      if v_credit > 0 then
        insert into public.night_payment(tenant_id, store_id, visit_id, method, amount)
        values (t_id, s_id, v_id, 'credit', v_credit);
        insert into public.night_receivable(
          tenant_id, store_id, customer_id, visit_id, occurred_on, amount, due_on)
        select t_id, s_id, customer_id, v_id, d, v_credit, d + 30
          from public.night_visit where id = v_id;
      elsif i % 3 = 0 then
        insert into public.night_payment(tenant_id, store_id, visit_id, method, amount)
        values (t_id, s_id, v_id, 'card', v_total);
      else
        insert into public.night_payment(tenant_id, store_id, visit_id, method, amount)
        values (t_id, s_id, v_id, 'cash', v_total);
      end if;

      update public.night_visit
         set status = 'closed',
             left_at = entered_at + interval '110 minutes',
             paid_cash   = case when v_credit > 0 then 0 when i % 3 = 0 then 0 else v_total end,
             paid_card   = case when v_credit = 0 and i % 3 = 0 then v_total else 0 end,
             paid_credit = v_credit,
             closed_at   = (d + 1 + time '01:30') at time zone 'Asia/Tokyo'
       where id = v_id;

      update public.night_customer
         set visit_count = visit_count + 1, last_visit_on = d
       where id = (select customer_id from public.night_visit where id = v_id);
    end loop;

    -- 日払い（あやは毎日1万、みなみは隔日8千）
    insert into public.night_payout(tenant_id, store_id, cast_id, business_date, amount, memo)
    values (t_id, s_id, c_aya, d, 10000, '当日日払い');
    if i % 2 = 0 then
      insert into public.night_payout(tenant_id, store_id, cast_id, business_date, amount, memo)
      values (t_id, s_id, c_min, d, 8000, '当日日払い');
    end if;

    -- 日締め（3日前までは実査も入れておく。1件だけ現金差異あり）
    insert into public.night_daily_close(
      tenant_id, store_id, business_date, sales_total, cash_expected, cash_counted,
      card_total, credit_total, visit_count, closed_at)
    select t_id, s_id, d,
           coalesce(sum(total),0), coalesce(sum(paid_cash),0),
           coalesce(sum(paid_cash),0) - case when i = 3 then 2000 else 0 end,
           coalesce(sum(paid_card),0), coalesce(sum(paid_credit),0), count(*),
           (d + 1 + time '02:00') at time zone 'Asia/Tokyo'
      from public.night_visit
     where store_id = s_id and business_date = d and status = 'closed'
    on conflict (store_id, business_date) do nothing;

  end loop;

  -- 手当・控除を少し
  insert into public.night_adjustment(tenant_id, store_id, cast_id, business_date, kind, name, amount)
  values (t_id, s_id, c_aya, current_date - 1, 'allowance', '皆勤手当', 5000),
         (t_id, s_id, c_min, current_date - 2, 'allowance', '同伴手当（追加）', 3000);

  -- ツケの一部入金（1件だけ「一部入金」の状態にする）
  insert into public.night_receivable_log(tenant_id, receivable_id, kind, amount, memo)
  select t_id, id, 'payment', floor(amount / 2), '本人来店時に受領'
    from public.night_receivable
   where store_id = s_id order by occurred_on limit 1;

  raise notice 'デモの実績を入れました。';
end $$;


-- ============================================================================
--  確認用
--
--   select business_date, visit_count, sales_total, cash_diff
--     from public.night_daily_close order by business_date desc;
--
--   select * from public.night_payroll_preview(
--     (select id from public.store where name='三宮本店'),
--     current_date - 7, current_date);
-- ============================================================================
