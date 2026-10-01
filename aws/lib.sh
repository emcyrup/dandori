# 共通：スタック名・リージョンと、スタックの出力を読む小道具（ほかのスクリプトから読み込む）
STACK="${STACK:-dandori-night}"
REGION="${AWS_REGION:-ap-northeast-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

out() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
