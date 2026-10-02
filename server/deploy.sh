#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 本番サーバーへ配備する（Docker なし・PM2 で動かす）
#
#    ./deploy.sh --init       はじめての配備（DB の初期設定 → 起動 → テーブル作成 → 確認）
#    ./deploy.sh              2回目から（git pull のあと。入れ替えて確認。DB はさわらない）
#    ./deploy.sh --sql FILE   2_データベース の SQL を1つ流す（仕上げ post.sql まで自動）
#    ./deploy.sh --auto       初回なら --init、2回目からは通常（GitHub Actions が使う）
#    ./deploy.sh --status     動いているか見る
#    ./deploy.sh --stop       全部止める
#
#  DB の操作だけしたいときは ./db.sh を使います（sql / demo / import）。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "!! .env がありません。先に ./install.sh → ./setup.sh"; exit 1; }
[ -x bin/postgrest ] && [ -x bin/auth ] && [ -x bin/deno ] && [ -d node_modules/pm2 ] || { echo "!! 部品が足りません。先に ./install.sh"; exit 1; }
set -a; . ./.env; set +a
PM2="./node_modules/.bin/pm2"
MIG="../aws/migrator/migrate.sh"
export PGHOST="$DB_HOST" PGPORT="${DB_PORT:-5432}" PGDATABASE="$DB_NAME" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${DB_SSLMODE:-prefer}"
export SQL_DIR="$(cd ../2_データベース && pwd)"
export AUTHENTICATOR_PASSWORD AUTH_ADMIN_PASSWORD STORAGE_ADMIN_PASSWORD SOURCE_DB_URL
URL="http://127.0.0.1:${LISTEN_PORT:-8032}"

precheck_db() {
  echo "== DB の確認（$DB_USER@$DB_HOST/$DB_NAME）"
  psql -X -tA -v ON_ERROR_STOP=1 <<'SQL' > /tmp/dandori-precheck.$$ || { echo "!! DB に接続できません（.env の DB_* を確認）"; exit 1; }
select
  (select rolcreaterole from pg_roles where rolname = current_user),
  (select count(*) = 6 from pg_roles where rolname in ('anon','authenticated','service_role','authenticator','supabase_auth_admin','supabase_storage_admin')),
  (select pg_get_userbyid(datdba) = current_user from pg_database where datname = current_database()),
  (select exists (select 1 from pg_roles where rolname = 'postgres')),
  current_setting('server_version_num')::int >= 150000;
SQL
  IFS='|' read -r can_create roles_ok is_owner has_pg ver_ok < /tmp/dandori-precheck.$$; rm -f /tmp/dandori-precheck.$$
  printf '   役割を作れる: %s / 役割がそろっている: %s / DB の持ち主: %s / postgres 役割: %s / PostgreSQL 15 以上: %s\n' "$can_create" "$roles_ok" "$is_owner" "$has_pg" "$ver_ok"
  if [ "$can_create" != "t" ] && [ "$roles_ok" != "t" ]; then
    echo "!! 役割（anon / authenticated など）が無く、作る権限もありません。"
    echo "   db/依頼_DB権限.sql を DB 管理者に渡して、役割を作ってもらってください。"
    exit 1
  fi
  [ "$is_owner" = "t" ] || { echo "!! $DB_NAME の持ち主が $DB_USER ではありません。管理者に ALTER DATABASE $DB_NAME OWNER TO $DB_USER; を頼んでください"; exit 1; }
  [ "$ver_ok" = "t" ] || { echo "!! PostgreSQL 15 以上が必要です"; exit 1; }
}

wait_http() {  # wait_http <URL> <説明>
  for _ in $(seq 1 60); do curl -sf "$1" >/dev/null && return 0; sleep 2; done
  echo "!! $2 が起きてきません。ログ: ./node_modules/.bin/pm2 logs"; exit 1
}

check() {
  echo "== 動作確認"
  wait_http "$URL/health" "入口"
  ok() { printf '   %-12s %s\n' "$1" "$2"; }
  ok 入口     "$(curl -s -o /dev/null -w %{http_code} $URL/login.html)"
  ok ログイン "$(curl -s -o /dev/null -w %{http_code} $URL/auth/v1/health)"
  ok データ   "$(curl -s -o /dev/null -w %{http_code} -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" $URL/rest/v1/)"
  ok ファイル "$(curl -s -o /dev/null -w %{http_code} $URL/storage/v1/status)"
  ok 関数     "$(curl -s -o /dev/null -w %{http_code} -X POST -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d '{}' $URL/functions/v1/send-outbox)"
  ok 公開URL  "$(curl -s -m 10 -o /dev/null -w %{http_code} "$SITE_URL/login.html" || echo '--')"
  $PM2 ls | grep -E "│ (rest|auth|storage|gateway|fn-|outbox)" | awk -F'│' '{gsub(/ /,"",$3); gsub(/ /,"",$10); printf "   %-16s %s\n", $3, $10}' || true
  echo "== 完了: $SITE_URL/"
}

reboot_hook() {  # サーバー再起動後に自分で立ち上がるように（crontab が使えるときだけ）
  local line="@reboot cd $(pwd) && ./node_modules/.bin/pm2 resurrect >/dev/null 2>&1"
  command -v crontab >/dev/null || { echo "   （crontab が無いので、再起動後は ./deploy.sh を実行してください）"; return 0; }
  if (crontab -l 2>/dev/null | grep -v "pm2 resurrect"; echo "$line") | crontab - 2>/dev/null; then
    echo "   再起動後の自動起動を crontab に登録しました"
  else
    echo "   （crontab が使えないので、再起動後は ./deploy.sh を実行してください）"
  fi
}

MODE="${1:-}"
if [ "$MODE" = "--auto" ]; then
  if [ "$(psql -X -tAc "select to_regclass('public.tenant') is not null" 2>/dev/null)" = "t" ] && $PM2 describe gateway >/dev/null 2>&1; then
    MODE=""; echo "== 2回目以降の配備として進めます"
  else
    MODE="--init"; echo "== 初回の配備として進めます"
  fi
fi

case "$MODE" in
  --init)
    precheck_db
    echo "== DB の初期設定（役割・権限）"
    bash "$MIG" bootstrap
    echo "== ファイル置き場の表"
    PGUSER=supabase_storage_admin PGPASSWORD="$STORAGE_ADMIN_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 -f db/storage-schema.sql
    echo "== ログイン（GoTrue）を先に起動して、テーブルを作らせる"
    $PM2 start ecosystem.config.cjs --only auth >/dev/null
    wait_http "http://127.0.0.1:${AUTH_PORT:-38033}/health" "ログイン"
    echo "== テーブル作成（2_データベース を全部）"
    bash "$MIG" schema
    echo "== 全部起動"
    $PM2 start ecosystem.config.cjs >/dev/null
    $PM2 save >/dev/null
    reboot_hook
    check
    ;;
  --sql)
    [ -n "${2:-}" ] || { echo "使い方: ./deploy.sh --sql ファイル名.sql"; exit 2; }
    bash "$MIG" schema "$2"
    ;;
  --status) $PM2 ls; check ;;
  --stop)   $PM2 delete all; echo "== 止めました" ;;
  "")
    echo "== 入れ替え"
    npm install --no-audit --no-fund --omit=dev 2>&1 | tail -1
    $PM2 startOrReload ecosystem.config.cjs >/dev/null
    $PM2 save >/dev/null
    check
    ;;
  *) sed -n '4,12p' "$0"; exit 2 ;;
esac
