#!/bin/sh
# 起動のたびに 1_画面 を /site に写し、config.js の接続先をこのサーバーに向ける。
# （リポジトリの config.js は Supabase 向けのまま。末尾で上書きするだけ）
set -eu
rm -rf /site && cp -R /site-src /site && rm -f /site/_headers
cat >> /site/config.js <<JS

// ---- 本番サーバー用（起動時に自動で追記）
window.DANDORI_CONFIG.supabaseUrl = "${SITE_URL}";
window.DANDORI_CONFIG.supabaseAnonKey = "${ANON_KEY}";
JS
