#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / データベース係を AWS の中で1回だけ動かす
#
#  使い方:  STACK=dandori-night ./aws/run-migrator.sh <コマンド> [引数...]
#    bootstrap                       役割・権限の初期設定（最初に1回）
#    schema                          2_データベース の SQL を全部流す
#    schema だんどり共通_017-027.sql   指定した SQL だけ流す
#    import                          Supabase から本番データを移す
#    demo                            デモデータを入れる
#    sql "select ..."                SQL を1文実行
#
#  RDS はインターネットから見えない場所にあるので、手元の psql からは繋がりません。
#  かわりに、この係（ECS タスク）が VPC の中から実行して、結果を表示します。
# ============================================================================
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || { sed -n '4,13p' "$0"; exit 2; }

CLUSTER="$(out ClusterName)"
TASKDEF="$(out MigratorTaskDefinition)"
SUBNETS="$(out TaskSubnets)"
SG="$(out TaskSecurityGroup)"
LOGS="$(out LogGroupName)"

CMD_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
OVERRIDES="{\"containerOverrides\":[{\"name\":\"migrator\",\"command\":$CMD_JSON}]}"

echo "== 実行: $*"
TASK_ARN="$(aws ecs run-task --cluster "$CLUSTER" --task-definition "$TASKDEF" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=ENABLED}" \
  --overrides "$OVERRIDES" --query 'tasks[0].taskArn' --output text)"
TASK_ID="${TASK_ARN##*/}"
echo "   タスク $TASK_ID（終わるまで待ちます）"
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"

aws logs get-log-events --log-group-name "$LOGS" \
  --log-stream-name "migrator/migrator/$TASK_ID" --start-from-head \
  --query 'events[].message' --output text | tr '\t' '\n' || true

CODE="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)"
if [ "$CODE" = "0" ]; then echo "== 成功"; else
  echo "!! 失敗（exit $CODE）"
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
    --query 'tasks[0].[stoppedReason,containers[0].reason]' --output text
  exit 1
fi
