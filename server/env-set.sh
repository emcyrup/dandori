#!/usr/bin/env bash
# .env の1項目を入れ替える（無ければ足す）。GitHub Actions が Secrets を流し込むときに使う。
#   ./env-set.sh KEY VALUE        VALUE が空のときは何もしない
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || cp .env.example .env
chmod 600 .env
key="$1"; val="${2:-}"
[[ "$key" =~ ^[A-Z0-9_]+$ ]] || { echo "!! 変な項目名: $key"; exit 2; }
[ -n "$val" ] || exit 0
esc="$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')"
if grep -qE "^$key=" .env; then
  sed -i "s|^$key=.*|$key=$esc|" .env
else
  printf '%s=%s\n' "$key" "$val" >> .env
fi
