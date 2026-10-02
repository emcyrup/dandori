#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 本番サーバーへ配備する
#
#    ./deploy.sh --init     はじめての配備（DB の初期設定 → 起動 → テーブル作成 → 確認）
#    ./deploy.sh            2回目から（作り直して入れ替え。DB はさわらない）
#    ./deploy.sh --sql FILE 2_データベース の SQL を1つ流す（仕上げ post.sql まで自動）
#
#  DB の操作だけしたいときは:
#    docker compose run --rm migrator sql "select ..."
#    docker compose run --rm migrator demo        デモデータ
#    docker compose run --rm migrator import      Supabase から移す（.env の SOURCE_DB_URL）
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "!! .env がありません。先に ./setup.sh"; exit 1; }
set -a; . ./.env; set +a
DC="docker compose"
M="$DC run --rm migrator"

echo "== 作成（コンテナのビルド）"
$DC build
$DC --profile tools build migrator

case "${1:-}" in
  --init)
    echo "== DB の初期設定（役割・権限）"
    $M bootstrap
    echo "== 起動"
    $DC up -d
    echo "== テーブル作成（ログイン・ファイルの準備ができるのを待ってから）"
    $M schema
    ;;
  --sql)
    [ -n "${2:-}" ] || { echo "使い方: ./deploy.sh --sql ファイル名.sql"; exit 2; }
    $DC up -d
    $M schema "$2"
    ;;
  "")
    echo "== 入れ替え"
    $DC up -d --remove-orphans
    ;;
  *) sed -n '4,14p' "$0"; exit 2 ;;
esac

echo "== 動作確認"
for i in $(seq 1 30); do
  curl -sf "http://127.0.0.1:${LISTEN_PORT:-8032}/health" >/dev/null && break; sleep 2
done
ok() { printf '   %-10s %s\n' "$1" "$2"; }
ok 入口   "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:${LISTEN_PORT:-8032}/login.html)"
ok ログイン "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:${LISTEN_PORT:-8032}/auth/v1/health)"
ok データ  "$(curl -s -o /dev/null -w %{http_code} -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" http://127.0.0.1:${LISTEN_PORT:-8032}/rest/v1/)"
ok ファイル "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:${LISTEN_PORT:-8032}/storage/v1/status)"
ok 公開URL "$(curl -s -o /dev/null -w %{http_code} "$SITE_URL/login.html")"
echo "== 完了: $SITE_URL/"
