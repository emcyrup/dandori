#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 本番サーバーの初回準備（1回だけ）
#   .env を作り、鍵（JWT と anon / service_role キー）と内部用パスワードを自動で入れます。
#   すでに .env があるときは、空の項目だけ埋めます（作ってある鍵は変えません）。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { cp .env.example .env; echo "== .env を作りました"; }
chmod 600 .env

get() { grep -E "^$1=" .env | head -1 | cut -d= -f2-; }
put() {  # 値が空のときだけ入れる
  if [ -z "$(get "$1")" ]; then
    sed -i "s|^$1=.*|$1=$2|" .env; echo "   $1 を作りました"
  fi
}
rnd() { openssl rand -hex "$1"; }
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
jwt() {  # HS256 で署名（Supabase の anon / service_role キーと同じ形）
  local head body sig
  head=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  body=$(printf '{"role":"%s","iss":"supabase","iat":1767225600,"exp":2082585600}' "$1" | b64url)
  sig=$(printf '%s' "$head.$body" | openssl dgst -sha256 -hmac "$2" -binary | b64url)
  printf '%s.%s.%s' "$head" "$body" "$sig"
}

put JWT_SECRET "$(rnd 24)"
SECRET="$(get JWT_SECRET)"
put ANON_KEY "$(jwt anon "$SECRET")"
put SERVICE_ROLE_KEY "$(jwt service_role "$SECRET")"
put AUTHENTICATOR_PASSWORD "$(rnd 16)"
put AUTH_ADMIN_PASSWORD "$(rnd 16)"
put STORAGE_ADMIN_PASSWORD "$(rnd 16)"
mkdir -p data/storage

missing=""
for k in SITE_URL DB_HOST DB_NAME DB_USER DB_PASSWORD; do [ -n "$(get $k)" ] || missing="$missing $k"; done
if [ -n "$missing" ]; then
  echo "!! .env にまだ入っていない項目があります:$missing"
  echo "   vi server/.env で入れてから、./deploy.sh --init を実行してください。"
  exit 1
fi
echo "== 準備できました。つぎは ./deploy.sh --init"
