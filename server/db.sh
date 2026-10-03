#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / データベースの操作（Supabase の SQL Editor の代わり）
#
#    ./db.sh sql "select ..."          SQL を1文流す
#    ./db.sh psql                      対話モード（\q で終了）
#    ./db.sh demo                      デモデータを入れる
#    ./db.sh import                    Supabase からデータを移す（.env の SOURCE_DB_URL）
#    ./db.sh schema [FILE.sql]         SQL を流す（省略で 2_データベース 全部 → stores/<店舗>/ 全部）→ 仕上げ
#    ./db.sh user-add メール パスワード 名前 [役割]   ログインとスタッフを作る（最初の店長など）
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "!! .env がありません。先に ./setup.sh"; exit 1; }
# .env を1行ずつそのまま読む（パスワードに $ や * があってもシェルに展開させない）
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key="${line%%=*}"; val="${line#*=}"
  [[ "$key" =~ ^[A-Z0-9_]+$ ]] && export "$key=$val"
done < .env
export PGHOST="$DB_HOST" PGPORT="${DB_PORT:-5432}" PGDATABASE="$DB_NAME" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${DB_SSLMODE:-prefer}"
export SQL_DIR="$(cd ../2_データベース && pwd)"
STORE="$(echo "${STORE:-dandori}" | tr -cd 'A-Za-z0-9_-' | tr 'A-Z' 'a-z')"; STORE="${STORE:-dandori}"
[ -d "../stores/$STORE" ] && export STORE_SQL_DIR="$(cd "../stores/$STORE" && pwd)" || export STORE_SQL_DIR=""
export AUTHENTICATOR_PASSWORD AUTH_ADMIN_PASSWORD STORAGE_ADMIN_PASSWORD SOURCE_DB_URL DB_MODE
MIG="../aws/migrator/migrate.sh"
# 運用スクリプトからの psql は「関数内」と同じ扱いにして RLS を素通りさせる（単一ロールモード用。役割ありでは無害）
export PGAPPNAME=dandori_fn

case "${1:-}" in
  psql) psql ;;
  user-add)
    [ $# -ge 4 ] || { echo "使い方: ./db.sh user-add メール パスワード 名前 [owner|manager|staff]"; exit 2; }
    URL="http://127.0.0.1:${LISTEN_PORT:-8032}"
    body="$(node -e 'console.log(JSON.stringify({email:process.argv[1],password:process.argv[2],email_confirm:true}))' "$2" "$3")"
    r="$(curl -s -X POST "$URL/auth/v1/admin/users" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "apikey: $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d "$body")"
    if echo "$r" | grep -q '"id"'; then echo "   ログインを作りました"
    elif echo "$r" | grep -q 'email_exists'; then echo "   ログインはすでにあります（スタッフの紐づけだけ行います）"
    else echo "!! ログインを作れませんでした: $r"; exit 1; fi
    # 紐づける法人：店舗名（STORE）と同じ名前の法人があればそれ、無ければ最初に作られた法人
    psql -X -v ON_ERROR_STOP=1 -c "select s.name, s.role, t.name as tenant
      from app.link_staff('$2', '$4', '${5:-owner}',
             coalesce((select id from public.tenant where lower(name) = lower('$STORE') limit 1),
                      (select id from public.tenant order by created_at limit 1))) s
      join public.tenant t on t.id = s.tenant_id"
    ;;
  schema)
    # 単一ロールモードでは、SQL を流す間だけ FORCE RLS が外れる（pre-single.sql）。
    # その間に画面から他の法人のデータが見えないよう、API を止めてから流し、終わったら戻す。
    if [ "${DB_MODE:-}" = "single" ] && [ -x ./node_modules/.bin/pm2 ] && ./node_modules/.bin/pm2 describe "$STORE-rest" >/dev/null 2>&1; then
      # 止めるもの：rest / storage / fn-*（名前は ecosystem.config.cjs と同じ付け方。pm2 の一覧出力は警告行が混ざるので使わない）
      API="$STORE-rest $STORE-storage"
      for d in ../3_サーバー/*/; do [ -f "$d/index.ts" ] && API="$API $STORE-fn-$(basename "$d")"; done
      echo "== SQL を流す間、API を止めます（$API）"
      ./node_modules/.bin/pm2 stop $API >/dev/null 2>&1 || true
      trap 'echo "== API を戻します"; ./node_modules/.bin/pm2 start '"$API"' >/dev/null 2>&1 || true' EXIT
    fi
    bash "$MIG" schema "$@" ;;
  sql|demo|import|bootstrap) bash "$MIG" "$@" ;;
  *) sed -n '4,11p' "$0"; exit 2 ;;
esac
