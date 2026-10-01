#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 画面（1_画面）を AWS に配る
#
#  使い方:  STACK=dandori-night ./aws/deploy.sh
#
#  1. 1_画面 の JS を node --check で確認
#  2. config.js の接続先を、AWS 版（同じアドレス + AWS の anon キー）に差し替えた写しを作る
#     （リポジトリの config.js は書き換えません）
#  3. S3 に同期して、CloudFront のキャッシュを消す
# ============================================================================
set -euo pipefail
. "$(dirname "$0")/lib.sh"
SITE="$ROOT/1_画面"

echo "== 文法チェック"
for f in "$SITE"/*.js; do node --check "$f"; done
echo "   OK"

BUCKET="$(out BucketName)"
DIST="$(out DistributionId)"
URL="$(out SiteUrl)"
ANON="$(aws secretsmanager get-secret-value --secret-id "$(out ApiKeysSecretArn)" \
  --query SecretString --output text | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).anon_key))')"

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$SITE"/. "$STAGE"/
rm -f "$STAGE/_headers"
URL="$URL" ANON="$ANON" node -e '
  const fs = require("fs"), p = process.argv[1];
  let s = fs.readFileSync(p, "utf8");
  const a = s.replace(/supabaseUrl:\s*"[^"]*"/, "supabaseUrl: " + JSON.stringify(process.env.URL))
             .replace(/supabaseAnonKey:\s*"[^"]*"/, "supabaseAnonKey: " + JSON.stringify(process.env.ANON));
  if (a === s || !a.includes(process.env.ANON)) { console.error("config.js の書き換えに失敗"); process.exit(1); }
  fs.writeFileSync(p, a);
' "$STAGE/config.js"
node --check "$STAGE/config.js"
echo "== 接続先: $URL"

echo "== S3 へ同期: s3://$BUCKET"
aws s3 sync "$STAGE" "s3://$BUCKET" --delete --exclude ".DS_Store" \
  --cache-control "public, max-age=0, must-revalidate"

echo "== CloudFront のキャッシュを削除"
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" \
  --query "Invalidation.Id" --output text

echo "== 完了: $URL/"
