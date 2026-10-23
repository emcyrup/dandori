-- ============================================================================
--  ナイトだんどり / Olivia のお店・メニュー・キャスト（この店舗だけの設定）
--  stores/olivia/store.sql
--
--  2_データベース（全店共通）を流したあとに流します。
--
--  メニュー表（Price List / Drink / Bottle / Champagne）を、そのまま料金マスタにしています。
--  何度流しても壊れません（「Olivia」がすでにあれば何もしません）。
--
--  【バックのきまり（いただいた内容）】
--    ・すべて小計（税・サービス料を含まない金額）に対する %
--    ・ドリンク 25% ／ シャンパン 10% ／ ボトル 10% ／ 同伴 1件 2,000円
--    ・そのほか卓についた際の商品（セット・ソーダ・ピッチャーなど）10%（「予備バック」）
--    ・時給は全員 2,000円スタート
--    ・達成率スライド（150% / 200% / 300%）は、この SQL の最後で入れます
--
--  【料金まわり】
--    ・メニュー表の「別途 Tax 20%」は、小計に 20% を上乗せする形で入れています
--      （店舗の service_rate = 20、tax_rate = 0。伝票には「サービス料 20%」と出ます）
--    ・同伴の料金は 2,000円（2026-10-03 確認）
-- ============================================================================

do $$
declare
  t_id uuid;
  s_id uuid;
  n    integer;
begin
  if exists (select 1 from public.tenant where name = 'Olivia') then
    raise notice 'Olivia はすでにあります。何もしません。';
    return;
  end if;

  insert into public.tenant(name, industry, plan)
       values ('Olivia', 'night', 'standard')
       returning id into t_id;

  insert into public.store(tenant_id, name, industry, day_cutoff, service_rate, tax_rate, tax_included, ui_theme)
       values (t_id, 'Olivia', 'night', '05:00', 20.00, 0.00, false, 'dark')
       returning id into s_id;

  -- ---- Price List
  insert into public.night_menu(tenant_id, store_id, category, name, unit_price, back_amount, back_rate, sort_order) values
    (t_id, s_id, 'set',    'セット（無制限・ボトルキープ）※混雑時90分制', 6000, 0,  0, 10),
    (t_id, s_id, 'set',    'セット（60分・飲み放題）',                    5000, 0,  0, 11),
    (t_id, s_id, 'douhan', '同伴',                                       2000, 2000, 0, 40),
  -- ---- Drink（キャストに付くドリンクは小計の 25%）
    (t_id, s_id, 'drink',  'キャストドリンク',  2000, 0, 25, 50),
    (t_id, s_id, 'drink',  'ビール',            1500, 0, 25, 51),
    (t_id, s_id, 'drink',  'ショット 各種',     2000, 0, 25, 52),
    (t_id, s_id, 'drink',  'コカボム',          3000, 0, 25, 53),
    (t_id, s_id, 'drink',  'すらっと 各種',     1500, 0, 25, 54),
    (t_id, s_id, 'drink',  'チャミスル',        3000, 0, 25, 55),
    (t_id, s_id, 'other',  'ソーダ',             500, 0,  0, 90),
    (t_id, s_id, 'other',  'ピッチャー',        1000, 0,  0, 91),
  -- ---- Bottle（小計の 10%）
    (t_id, s_id, 'bottle', '吉四六',                    10000, 0, 10, 100),
    (t_id, s_id, 'bottle', '壱岐ゴールド',              10000, 0, 10, 101),
    (t_id, s_id, 'bottle', '黒霧島',                    10000, 0, 10, 102),
    (t_id, s_id, 'bottle', 'ダイヤメ',                  12000, 0, 10, 103),
    (t_id, s_id, 'bottle', '鍛高譚',                    10000, 0, 10, 104),
    (t_id, s_id, 'bottle', '柚子小町',                  10000, 0, 10, 110),
    (t_id, s_id, 'bottle', '茉莉花',                    10000, 0, 10, 111),
    (t_id, s_id, 'bottle', 'プルシア',                  13000, 0, 10, 112),
    (t_id, s_id, 'bottle', 'ミスティア',                13000, 0, 10, 113),
    (t_id, s_id, 'bottle', 'Six Eight Nine Napa Valley Red', 20000, 0, 10, 120),
    (t_id, s_id, 'bottle', 'Chablis',                   20000, 0, 10, 121),
    (t_id, s_id, 'bottle', '山崎 ST',                   30000, 0, 10, 130),
    (t_id, s_id, 'bottle', '白州 ST',                   30000, 0, 10, 131),
    (t_id, s_id, 'bottle', '角瓶',                      13000, 0, 10, 132),
    (t_id, s_id, 'bottle', 'シーバス・ミズナラ 12年',   20000, 0, 10, 133),
    (t_id, s_id, 'bottle', 'ヘネシー VS',               25000, 0, 10, 140),
  -- ---- Champagne（種類は champagne。売上の内訳でボトルと分けて見られます）
    (t_id, s_id, 'champagne', 'Veuve Clicquot Yellow Label',                 26000, 0, 10, 200),
    (t_id, s_id, 'champagne', 'Veuve Clicquot White Label',                  30000, 0, 10, 201),
    (t_id, s_id, 'champagne', 'Moët & Chandon Nectar Impérial Rosé',         42000, 0, 10, 202),
    (t_id, s_id, 'champagne', 'Xavier-L-Vuitton Bouzy Grand Cru Brut Millésimé', 60000, 0, 10, 203),
    (t_id, s_id, 'champagne', 'Soumei Brut',                                 70000, 0, 10, 204),
    (t_id, s_id, 'champagne', 'Perrier-Jouët Belle Époque',                  80000, 0, 10, 205),
    (t_id, s_id, 'champagne', 'Dom Pérignon',                                80000, 0, 10, 210),
    (t_id, s_id, 'champagne', 'Dom Pérignon Luminous',                      100000, 0, 10, 211),
    (t_id, s_id, 'champagne', 'Louis Roederer Cristal',                     160000, 0, 10, 212),
    (t_id, s_id, 'champagne', 'Armand de Brignac Brut Gold',                140000, 0, 10, 213),
    (t_id, s_id, 'champagne', 'Armand de Brignac Rosé',                     210000, 0, 10, 214),
    (t_id, s_id, 'champagne', 'Armand de Brignac Brut Green Golfer''s Edition', 260000, 0, 10, 215);

  get diagnostics n = row_count;

  -- ---- キャスト（全員 時給 2,000円スタート）
  insert into public.night_cast(tenant_id, store_id, name, hourly_wage, joined_on) values
    (t_id, s_id, 'あやね', 2000, current_date),
    (t_id, s_id, 'みらい', 2000, current_date),
    (t_id, s_id, 'せりほ', 2000, current_date),
    (t_id, s_id, 'らな',   2000, current_date),
    (t_id, s_id, 'ゆいか', 2000, current_date),
    (t_id, s_id, 'みのり', 2000, current_date),
    (t_id, s_id, 'せりな', 2000, current_date);

  raise notice 'Olivia を作りました。メニュー % 件、キャスト 7 名。店舗ID: %', n, s_id;
end $$;

-- 確認用：
-- select category, name, unit_price, back_amount, back_rate from public.night_menu
--  where store_id = (select id from public.store where name = 'Olivia') order by sort_order;


-- ----------------------------------------------------------------------------
--  Olivia のキャストに、達成率スライドを入れる（まだ何も設定していない人だけ）
--       150% … 時給 2,500円
--       200% … 時給 2,500円 ＋ バック下限 20%
--       300% … 時給 3,000円 ＋ バック下限 20%
-- ----------------------------------------------------------------------------
update public.night_cast
   set wage_rules = '[{"type":"ratio","from":150,"wage":2500},
                      {"type":"ratio","from":200,"wage":2500,"back_rate":20},
                      {"type":"ratio","from":300,"wage":3000,"back_rate":20}]'::jsonb
 where store_id in (select id from public.store where name = 'Olivia')
   and wage_rules = '[]'::jsonb;


-- ----------------------------------------------------------------------------
--  2026-10-03 の追加（すでに Olivia が入っている環境にも効くように、ここで直す）
--    ・予備バック 10%：卓についた際の商品（10-13 から、卓の小計の折半ぶんに付ける）
--    ・同伴の料金を 2,000円に
-- ----------------------------------------------------------------------------
-- （予備バックは 2026-10-13 から、明細ごとではなく卓の小計の折半ぶんに付けます。下の 10-13 の取り決めを参照）

update public.night_menu
   set unit_price = 2000
 where store_id in (select id from public.store where name = 'Olivia')
   and category = 'douhan' and unit_price = 0;

-- ----------------------------------------------------------------------------
--  AI の下書きは Claude（Anthropic）を使う（鍵は GitHub Secrets の ANTHROPIC_API_KEY）。
--  まだ何も選んでいない法人だけ。管理画面「AI・送信」で変えられる
-- ----------------------------------------------------------------------------
insert into public.tenant_ai(tenant_id, ai_provider)
select id, 'claude' from public.tenant where name = 'Olivia'
on conflict (tenant_id) do nothing;


-- ----------------------------------------------------------------------------
--  2026-10-13 の取り決め（032_olivia_rules.sql の店舗設定）
--    ・会計は〇万〇千円にそろえる（百円台が 500 以上は切り上げ、未満は切り下げ）
--    ・打刻は 30 分単位（出勤は次の 30 分、退勤は前の 30 分）
--    ・給与は総支給から一律 10% を控除
--    ・卓についたキャストを「指名」として数え、伝票の小計をついた人数で均等に分ける（折半）
--    ・予備バック 10% は、個人売上（小計を人数で割ったぶん）に付ける（10-14 に Excel に合わせて変更）
--      → セット・ソーダ・ピッチャー・ボトル・シャンパンの明細ごとのバックは 0 にする（二重払いを防ぐ）
--      → ドリンク 25%・同伴 2,000 円は、これまでどおり「誰にバックを付けますか？」で選んだ人に付く（Excel の「その他」「同伴」）
-- ----------------------------------------------------------------------------
update public.store
   set bill_round = 1000, clock_round = 30, pay_withhold_pct = 10,
       seat_split = true, table_back_pct = 10
 where name = 'Olivia';

update public.night_menu
   set back_rate = 0, back_amount = 0
 where store_id in (select id from public.store where name = 'Olivia')
   and category in ('set', 'extension', 'food', 'other', 'bottle');


-- ----------------------------------------------------------------------------
--  2026-10-14 給与 Excel に合わせる（ただし 200% 以上のバック 20% は、Excel と違い実際に 20% で払う）
--    ・達成率 ＝ 個人売上 ÷（基本時給 × 時間 ＋ バック10% ＋ その他 ＋ 同伴 ＋ 10時IN）
--    ・時給：50% 未満 1,500 ／ 50% 以上 2,000 ／ 150% 以上 2,500 ／ 300% 以上 3,000
--    ・バック：個人売上 × 10%（200% 以上は 20%）
--    ・10時IN：1 回 1,000 円（出勤の画面で日ごとに付ける）
-- ----------------------------------------------------------------------------
update public.store set ratio_base = 'pay', in10_amount = 1000 where name = 'Olivia';

-- 前の段階（150/200/300）のままの人、まだ何も設定していない人だけ置きかえる（個別に変えた人はそのまま）
update public.night_cast
   set wage_rules = '[{"type":"ratio_under","under":50,"wage":1500},
                      {"type":"ratio","from":150,"wage":2500},
                      {"type":"ratio","from":200,"wage":2500,"back_rate":20},
                      {"type":"ratio","from":300,"wage":3000,"back_rate":20}]'::jsonb
 where store_id in (select id from public.store where name = 'Olivia')
   and (wage_rules = '[]'::jsonb
        or wage_rules = '[{"type":"ratio","from":150,"wage":2500},
                          {"type":"ratio","from":200,"wage":2500,"back_rate":20},
                          {"type":"ratio","from":300,"wage":3000,"back_rate":20}]'::jsonb);


-- ----------------------------------------------------------------------------
--  2026-10-15 シャンパンを「ボトル」から種類 champagne に分ける（033_champagne.sql）
--    すでに入っている Olivia のメニューと、過去の伝票の明細も付け替える（売上の内訳が分かれる）
-- ----------------------------------------------------------------------------
update public.night_menu
   set category = 'champagne'
 where store_id in (select id from public.store where name = 'Olivia')
   and category = 'bottle' and sort_order between 200 and 299;

update public.night_visit_item i
   set category = 'champagne'
  from public.night_menu m
 where m.id = i.menu_id and m.category = 'champagne' and i.category = 'bottle';

-- ----------------------------------------------------------------------------
--  2026-10-23：シフトの募集は一週間ごと（月〜土）。ボトルのプルダウンの見出し
-- ----------------------------------------------------------------------------
update public.store set wish_cycle = 'week6'
 where name = 'Olivia' and tenant_id in (select id from public.tenant where name = 'Olivia')
   and coalesce(wish_cycle, '') <> 'week6';

update public.night_menu m set group_name = g.label
  from (values
    ('吉四六', '焼酎・リキュール'), ('壱岐ゴールド', '焼酎・リキュール'), ('黒霧島', '焼酎・リキュール'),
    ('ダイヤメ', '焼酎・リキュール'), ('鍛高譚', '焼酎・リキュール'), ('柚子小町', '焼酎・リキュール'),
    ('茉莉花', '焼酎・リキュール'), ('プルシア', '焼酎・リキュール'), ('ミスティア', '焼酎・リキュール'),
    ('Six Eight Nine Napa Valley Red', 'ワイン'), ('Chablis', 'ワイン'),
    ('山崎 ST', 'ウイスキー・ブランデー'), ('白州 ST', 'ウイスキー・ブランデー'), ('角瓶', 'ウイスキー・ブランデー'),
    ('シーバス・ミズナラ 12年', 'ウイスキー・ブランデー'), ('ヘネシー VS', 'ウイスキー・ブランデー')
  ) as g(name, label)
 where m.name = g.name and m.category = 'bottle' and m.group_name is distinct from g.label
   and m.tenant_id in (select id from public.tenant where name = 'Olivia');
