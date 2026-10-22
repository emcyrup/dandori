#!/usr/bin/env bash
# .env の1項目を入れ替える（無ければ足す）。GitHub Actions が Secrets を流し込むときに使う。
#   ./env-set.sh KEY VALUE        VALUE が空のときは何もしない
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || cp .env.example .env
chmod 600 .env
key="$1"; val="${2:-}"
[[ "$key" =~ ^[A-Z0-9_]+$ ]] || { echo "!! 変な項目名: $key"; exit 2; }
# 値が引数に無ければ標準入力から（鍵やパスワードを ps に出さないため）
if [ -z "$val" ] && [ ! -t 0 ]; then val="$(cat)"; fi
[ -n "$val" ] || exit 0
case "$val" in *$'\n'*) echo "!! $key の値に改行が入っています"; exit 2 ;; esac
# sed を使わず、その行を外して書き直す（\ や & を含む値でも化けない）
tmp="$(mktemp .env.XXXXXX)"
grep -vE "^$key=" .env > "$tmp" || true
printf '%s=%s\n' "$key" "$val" >> "$tmp"
chmod 600 "$tmp" && mv -f "$tmp" .env
