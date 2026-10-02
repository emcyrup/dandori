#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / データベースの操作（Supabase の SQL Editor の代わり）
#
#    ./db.sh sql "select ..."          SQL を1文流す
#    ./db.sh psql                      対話モード（\q で終了）
#    ./db.sh demo                      デモデータを入れる
#    ./db.sh import                    Supabase からデータを移す（.env の SOURCE_DB_URL）
#    ./db.sh schema [FILE.sql]         2_データベース の SQL を流す（省略で全部）→ 仕上げ
#    ./db.sh user-add メール パスワード 名前 [役割]   ログインとスタッフを作る（最初の店長など）
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "!! .env がありません。先に ./setup.sh"; exit 1; }
set -a; . ./.env; set +a
export PGHOST="$DB_HOST" PGPORT="${DB_PORT:-5432}" PGDATABASE="$DB_NAME" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${DB_SSLMODE:-prefer}"
export SQL_DIR="$(cd ../2_データベース && pwd)"
export AUTHENTICATOR_PASSWORD AUTH_ADMIN_PASSWORD STORAGE_ADMIN_PASSWORD SOURCE_DB_URL
MIG="../aws/migrator/migrate.sh"

case "${1:-}" in
  psql) psql ;;
  user-add)
    [ $# -ge 4 ] || { echo "使い方: ./db.sh user-add メール パスワード 名前 [owner|manager|staff]"; exit 2; }
    URL="http://127.0.0.1:${LISTEN_PORT:-8032}"
    body="$(node -e 'console.log(JSON.stringify({email:process.argv[1],password:process.argv[2],email_confirm:true}))' "$2" "$3")"
    r="$(curl -s -X POST "$URL/auth/v1/admin/users" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "apikey: $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d "$body")"
    echo "$r" | grep -q '"id"' || { echo "!! ログインを作れませんでした: $r"; exit 1; }
    psql -X -c "select name, role from app.link_staff('$2', '$4', '${5:-owner}')"
    ;;
  sql|demo|import|schema|bootstrap) bash "$MIG" "$@" ;;
  *) sed -n '4,11p' "$0"; exit 2 ;;
esac
