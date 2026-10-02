#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 本番サーバーに部品を入れる（sudo 不要・ホームディレクトリ内だけ）
#
#    ./install.sh          足りないものだけ入れる
#    ./install.sh --force  入れ直す
#
#  入れるもの（版は固定）
#    bin/postgrest   データの受け口     PostgREST v14.17（単体バイナリ）
#    bin/auth        ログイン           GoTrue   v2.196.0（単体バイナリ + migrations/）
#    bin/deno        3_サーバー の実行  Deno     v2.6.3
#    node_modules/   pm2（起動管理）と pg（ファイル置き場が使う）
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
FORCE="${1:-}"
POSTGREST_VER=v14.17
GOTRUE_VER=v2.196.0
DENO_VER=v2.6.3

echo "== 事前確認"
for c in node npm curl tar xz unzip psql pg_dump; do
  command -v "$c" >/dev/null || { echo "!! $c がありません。サーバー管理者に入れてもらってください"; exit 1; }
done
NODE_MAJOR="$(node -e 'process.stdout.write(String(process.versions.node.split(".")[0]))')"
[ "$NODE_MAJOR" -ge 22 ] || { echo "!! Node.js 22 以上が必要です（いま $(node -v)）"; exit 1; }
echo "   node $(node -v) / psql $(psql --version | awk '{print $3}')"

mkdir -p bin data/storage data/deno logs
fetch() {  # fetch <URL> <保存先>
  echo "   取得: $1"
  curl -fsSL --retry 3 -o "$2" "$1"
}

if [ "$FORCE" = "--force" ] || [ ! -x bin/postgrest ]; then
  echo "== PostgREST $POSTGREST_VER"
  fetch "https://github.com/PostgREST/postgrest/releases/download/$POSTGREST_VER/postgrest-$POSTGREST_VER-linux-static-x86-64.tar.xz" bin/postgrest.tar.xz
  tar -xJf bin/postgrest.tar.xz -C bin && rm bin/postgrest.tar.xz
fi
if [ "$FORCE" = "--force" ] || [ ! -x bin/auth ]; then
  echo "== GoTrue $GOTRUE_VER"
  fetch "https://github.com/supabase/auth/releases/download/$GOTRUE_VER/auth-$GOTRUE_VER-x86.tar.gz" bin/auth.tar.gz
  tar -xzf bin/auth.tar.gz -C bin && rm bin/auth.tar.gz
fi
if [ "$FORCE" = "--force" ] || [ ! -x bin/deno ]; then
  echo "== Deno $DENO_VER"
  fetch "https://github.com/denoland/deno/releases/download/$DENO_VER/deno-x86_64-unknown-linux-gnu.zip" bin/deno.zip
  unzip -qo bin/deno.zip -d bin && rm bin/deno.zip
fi
chmod +x bin/postgrest bin/auth bin/deno

echo "== npm（pm2 / pg）"
npm install --no-audit --no-fund --omit=dev 2>&1 | tail -1

echo "== 確認"
printf '   %-10s %s\n' postgrest "$(bin/postgrest --version 2>&1 | head -1)"
printf '   %-10s %s\n' gotrue    "$(bin/auth version 2>&1 | head -1)"
printf '   %-10s %s\n' deno      "$(bin/deno --version | head -1)"
printf '   %-10s %s\n' pm2       "$(node_modules/.bin/pm2 -v)"
echo "== 完了。つぎは ./setup.sh"
