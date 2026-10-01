#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 画面を AWS (S3 + CloudFront) に配る
#
#  使い方:   ./aws/deploy.sh [スタック名]
#            （スタック名の既定は dandori-night、リージョンは AWS_REGION か ap-northeast-1）
#
#  1. 1_画面 の JS を node --check で確認（文法エラーがあれば止める）
#  2. S3 に同期（_headers は Netlify 用なので送らない）
#  3. CloudFront のキャッシュを消す
# ============================================================================
set -euo pipefail

STACK="${1:-dandori-night}"
REGION="${AWS_REGION:-ap-northeast-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$ROOT/1_画面"

echo "== 文法チェック"
if command -v node >/dev/null 2>&1; then
  for f in "$SITE"/*.js; do node --check "$f"; done
  echo "   OK"
else
  echo "   node が無いのでスキップ"
fi

out() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
BUCKET="$(out BucketName)"
DIST="$(out DistributionId)"
URL="$(out SiteUrl)"

echo "== S3 へ同期: s3://$BUCKET"
aws s3 sync "$SITE" "s3://$BUCKET" --region "$REGION" --delete \
  --exclude "_headers" --exclude ".DS_Store" \
  --cache-control "public, max-age=0, must-revalidate"

echo "== CloudFront のキャッシュを削除: $DIST"
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" \
  --query "Invalidation.Id" --output text

echo "== 完了: $URL"
