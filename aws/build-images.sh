#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 自前のコンテナ3つを作って ECR に入れる
#    gateway   … 入口（nginx）
#    functions … 3_サーバー の Edge Functions
#    migrator  … 2_データベース の SQL を流す係
#
#  使い方:  STACK=dandori-night ./aws/build-images.sh [タグ]
#           タグを省くと latest。API サーバーが動いていれば入れ替えまで行う。
# ============================================================================
set -euo pipefail
. "$(dirname "$0")/lib.sh"
TAG="${1:-latest}"

REGISTRY="$(out GatewayRepoUri | cut -d/ -f1)"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

for name in gateway functions migrator; do
  key="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}RepoUri"
  uri="$(out "$key")"
  echo "== $name → $uri:$TAG"
  docker build --platform linux/amd64 -f "$ROOT/aws/$name/Dockerfile" -t "$uri:$TAG" "$ROOT"
  docker push "$uri:$TAG"
done

CLUSTER="$(out ClusterName)"; SERVICE="$(out ServiceName)"
COUNT="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].desiredCount' --output text)"
if [ "$COUNT" != "0" ]; then
  echo "== API サーバーを入れ替え"
  aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --force-new-deployment \
    --query 'service.deployments[0].rolloutState' --output text
fi
echo "== 完了"
