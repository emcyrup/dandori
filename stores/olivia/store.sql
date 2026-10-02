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
--    ・時給は全員 2,000円スタート
--    ・達成率スライド（150% / 200% / 300%）は、この SQL の最後で入れます
--
--  【料金まわり】
--    ・メニュー表の「別途 Tax 20%」は、小計に 20% を上乗せする形で入れています
--      （店舗の service_rate = 20、tax_rate = 0。伝票には「サービス料 20%」と出ます）
--    ・同伴の料金は、メニュー表に無いので 0 円にしてあります。管理画面で直してください
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
    (t_id, s_id, 'douhan', '同伴',                                          0, 2000, 0, 40),
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
  -- ---- Champagne（小計の 10%）
    (t_id, s_id, 'bottle', 'Veuve Clicquot Yellow Label',                 26000, 0, 10, 200),
    (t_id, s_id, 'bottle', 'Veuve Clicquot White Label',                  30000, 0, 10, 201),
    (t_id, s_id, 'bottle', 'Moët & Chandon Nectar Impérial Rosé',         42000, 0, 10, 202),
    (t_id, s_id, 'bottle', 'Xavier-L-Vuitton Bouzy Grand Cru Brut Millésimé', 60000, 0, 10, 203),
    (t_id, s_id, 'bottle', 'Soumei Brut',                                 70000, 0, 10, 204),
    (t_id, s_id, 'bottle', 'Perrier-Jouët Belle Époque',                  80000, 0, 10, 205),
    (t_id, s_id, 'bottle', 'Dom Pérignon',                                80000, 0, 10, 210),
    (t_id, s_id, 'bottle', 'Dom Pérignon Luminous',                      100000, 0, 10, 211),
    (t_id, s_id, 'bottle', 'Louis Roederer Cristal',                     160000, 0, 10, 212),
    (t_id, s_id, 'bottle', 'Armand de Brignac Brut Gold',                140000, 0, 10, 213),
    (t_id, s_id, 'bottle', 'Armand de Brignac Rosé',                     210000, 0, 10, 214),
    (t_id, s_id, 'bottle', 'Armand de Brignac Brut Green Golfer''s Edition', 260000, 0, 10, 215);

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
