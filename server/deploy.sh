#!/usr/bin/env bash
# ============================================================================
#  ナイトだんどり / 本番サーバーへ配備する（Docker なし・PM2 で動かす）
#
#    ./deploy.sh --init       はじめての配備（DB の初期設定 → 起動 → テーブル作成 → 確認）
#    ./deploy.sh              2回目から（git pull のあと。入れ替えて確認。DB はさわらない）
#    ./deploy.sh --sql FILE   2_データベース の SQL を1つ流す（仕上げ post.sql まで自動）
#    ./deploy.sh --auto       初回なら --init、2回目からは通常（GitHub Actions が使う）
#    ./deploy.sh --status     動いているか見る
#    ./deploy.sh --stop       全部止める
#
#  DB の操作だけしたいときは ./db.sh を使います（sql / demo / import）。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "!! .env がありません。先に ./install.sh → ./setup.sh"; exit 1; }
[ -x bin/postgrest ] && [ -x bin/auth ] && [ -x bin/deno ] && [ -d node_modules/pm2 ] || { echo "!! 部品が足りません。先に ./install.sh"; exit 1; }
# .env を1行ずつそのまま読む（パスワードに $ や * があってもシェルに展開させない）
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key="${line%%=*}"; val="${line#*=}"
  [[ "$key" =~ ^[A-Z0-9_]+$ ]] && export "$key=$val"
done < .env
PM2="./node_modules/.bin/pm2"
MIG="../aws/migrator/migrate.sh"
# 運用スクリプトからの psql は「関数内」と同じ扱いにして RLS を素通りさせる（単一ロールモード用。役割ありでは無害）
export PGAPPNAME=dandori_fn
export PGHOST="$DB_HOST" PGPORT="${DB_PORT:-5432}" PGDATABASE="$DB_NAME" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${DB_SSLMODE:-prefer}"
export SQL_DIR="$(cd ../2_データベース && pwd)"
STORE="$(echo "${STORE:-dandori}" | tr -cd 'A-Za-z0-9_-' | tr 'A-Z' 'a-z')"; STORE="${STORE:-dandori}"
[ -d "../stores/$STORE" ] && export STORE_SQL_DIR="$(cd "../stores/$STORE" && pwd)" || export STORE_SQL_DIR=""
export AUTHENTICATOR_PASSWORD AUTH_ADMIN_PASSWORD STORAGE_ADMIN_PASSWORD SOURCE_DB_URL DB_MODE
URL="http://127.0.0.1:${LISTEN_PORT:-8032}"

precheck_db() {
  echo "== DB の確認（$DB_USER@$DB_HOST/$DB_NAME）"
  local pre; pre="$(mktemp)" || exit 1
  psql -X -tA -v ON_ERROR_STOP=1 <<'SQL' > "$pre" || { rm -f "$pre"; echo "!! DB に接続できません（.env の DB_* を確認）"; exit 1; }
select
  (select rolcreaterole from pg_roles where rolname = current_user),
  (select count(*) = 6 from pg_roles where rolname in ('anon','authenticated','service_role','authenticator','supabase_auth_admin','supabase_storage_admin')),
  (select pg_get_userbyid(datdba) = current_user from pg_database where datname = current_database()),
  (select exists (select 1 from pg_roles where rolname = 'postgres')),
  current_setting('server_version_num')::int >= 150000;
SQL
  IFS='|' read -r can_create roles_ok is_owner has_pg ver_ok < "$pre"; rm -f "$pre"
  printf '   役割を作れる: %s / 役割がそろっている: %s / DB の持ち主: %s / postgres 役割: %s / PostgreSQL 15 以上: %s\n' "$can_create" "$roles_ok" "$is_owner" "$has_pg" "$ver_ok"
  if [ "${DB_MODE:-}" = "single" ]; then
    echo "   単一ロールモード（DB ユーザー1つで動かす）"
  elif [ "$can_create" != "t" ] && [ "$roles_ok" != "t" ] && [ -z "${DB_ADMIN_PASSWORD:-}" ]; then
    echo "   役割を作れないので、単一ロールモード（DB ユーザー1つで動かす）にします"
    ./env-set.sh DB_MODE single; export DB_MODE=single
  elif [ "$can_create" != "t" ] && [ "$roles_ok" != "t" ]; then
    # 管理者のパスワードがあっても、その管理者に役割を作る権限が無ければ単一ロールモードにする
    admin_ok="$(PGUSER="${DB_ADMIN_USER:-postgres}" PGPASSWORD="$DB_ADMIN_PASSWORD" psql -X -tAc \
      "select rolsuper or rolcreaterole from pg_roles where rolname = current_user" 2>/dev/null || echo f)"
    if [ "$admin_ok" != "t" ]; then
      echo "   管理者（${DB_ADMIN_USER:-postgres}）でも役割を作れないので、単一ロールモード（DB ユーザー1つで動かす）にします"
      ./env-set.sh DB_MODE single; export DB_MODE=single
    else
      echo "== 管理者（${DB_ADMIN_USER:-postgres}）で役割を作ります"
      PGUSER="${DB_ADMIN_USER:-postgres}" PGPASSWORD="$DB_ADMIN_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 \
        -v app_user="$DB_USER" -v authenticator_pw="$AUTHENTICATOR_PASSWORD" \
        -v auth_admin_pw="$AUTH_ADMIN_PASSWORD" -v storage_admin_pw="$STORAGE_ADMIN_PASSWORD" \
        -f db/admin-roles.sql
      echo "   作りました"
    fi
  elif [ "$can_create" != "t" ] && [ -n "${DB_ADMIN_PASSWORD:-}" ]; then
    # 役割はあるが、この店舗のユーザーへの権限付与がまだかもしれないので、管理者で確かめておく
    PGUSER="${DB_ADMIN_USER:-postgres}" PGPASSWORD="$DB_ADMIN_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 \
      -v app_user="$DB_USER" -v authenticator_pw="$AUTHENTICATOR_PASSWORD" \
      -v auth_admin_pw="$AUTH_ADMIN_PASSWORD" -v storage_admin_pw="$STORAGE_ADMIN_PASSWORD" \
      -f db/admin-roles.sql
  fi
  [ "$is_owner" = "t" ] || { echo "!! $DB_NAME の持ち主が $DB_USER ではありません。管理者に ALTER DATABASE $DB_NAME OWNER TO $DB_USER; を頼んでください"; exit 1; }
  [ "$ver_ok" = "t" ] || { echo "!! PostgreSQL 15 以上が必要です"; exit 1; }
}

wait_http() {  # wait_http <URL> <説明>
  for _ in $(seq 1 60); do curl -sf "$1" >/dev/null && return 0; sleep 2; done
  echo "!! $2 が起きてきません。ログ: ./node_modules/.bin/pm2 logs"; exit 1
}

check() {
  echo "== 動作確認（店舗: $STORE）"
  wait_http "$URL/health" "入口"
  ok() { printf '   %-12s %s\n' "$1" "$2"; }
  ok 入口     "$(curl -s -o /dev/null -w %{http_code} $URL/login.html)"
  ok ログイン "$(curl -s -o /dev/null -w %{http_code} $URL/auth/v1/health)"
  ok データ   "$(curl -s -o /dev/null -w %{http_code} -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" "$URL/rest/v1/store?select=id&limit=1")"
  ok ファイル "$(curl -s -o /dev/null -w %{http_code} $URL/storage/v1/status)"
  ok 関数     "$(curl -s -o /dev/null -w %{http_code} -X POST -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d '{}' $URL/functions/v1/send-outbox)"
  ok 公開URL  "$(curl -s -m 10 -o /dev/null -w %{http_code} "$SITE_URL/login.html" || echo '--')"
  $PM2 ls | grep -E "│ $STORE-" | awk -F'│' '{gsub(/ /,"",$3); gsub(/ /,"",$10); printf "   %-22s %s\n", $3, $10}' || true
  if [ "$(psql -X -tAc "select to_regclass('public.security_event') is not null" 2>/dev/null)" = "t" ]; then
    echo "== 不正アクセスの見張り（24時間）"
    psql -X -tAc "select '   検知 ' || count(*) || ' 件、うち重要 ' || count(*) filter (where severity = 'high') || ' 件、止めている接続元 ' ||
                    (select count(*) from public.security_block where not released and until > now()) || ' か所'
                    from public.security_event where at > now() - interval '24 hours' and kind <> 'unblocked'" 2>/dev/null || true
  fi
  line_check
  echo "== 完了: $SITE_URL/"
}

# LINE 連携の確認（鍵そのものは表示しない）
#   ・シークレット／トークンが登録されているか、形が合っているか
#   ・トークンが LINE に通るか（api.line.me/v2/bot/info。トークンは標準入力で curl に渡し、ps に出さない）
#   ・LINE から最後に届いた時刻（シークレットが正しくないと、署名で断るので届かない）
line_check() {
  [ "$(psql -X -tAc "select to_regclass('public.tenant_secret') is not null" 2>/dev/null)" = "t" ] || return 0
  echo "== LINE 連携"
  psql -X -tA -F '|' -c "select t.id, t.name, coalesce(a.line_enabled, false),
           (select value from public.tenant_secret x where x.tenant_id = t.id and x.key_name = 'line_channel_secret'),
           (select count(*) from public.line_link l where l.tenant_id = t.id),
           (select count(*) from public.line_link l where l.tenant_id = t.id and l.subject_id is not null),
           coalesce((select to_char(max(l.last_seen_at) at time zone 'Asia/Tokyo', 'MM/DD HH24:MI') from public.line_link l where l.tenant_id = t.id), '—'),
           (select count(*) from public.outbox o where o.tenant_id = t.id and o.channel = 'line' and o.status = 'failed' and o.created_at > now() - interval '7 days'),
           (select count(*) from public.outbox o where o.tenant_id = t.id and o.channel = 'line' and o.status = 'sent' and o.created_at > now() - interval '7 days')
      from public.tenant t left join public.tenant_ai a on a.tenant_id = t.id
     where exists (select 1 from public.tenant_secret x where x.tenant_id = t.id and x.key_name like 'line_%')
     order by t.created_at" 2>/dev/null |
  while IFS='|' read -r tid tname enabled secret seen linked last failed sent; do
    if [ -z "$secret" ]; then sec="なし（受信できません）"
    elif [[ "$secret" =~ ^[0-9a-f]{32}$ ]]; then sec="あり（形 OK：32けた）"
    else sec="あり（形が変です：LINE のチャネルシークレットは英数32けた。前後の空白や別の値が入っていないか）"; fi
    tok="$(psql -X -tAc "select value from public.tenant_secret where tenant_id = '$tid' and key_name = 'line_channel_token'" 2>/dev/null)"
    if [ -z "$tok" ]; then tk="なし（送信できません）"
    else
      info="$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl -s -m 10 -K - -w '\n%{http_code}' https://api.line.me/v2/bot/info 2>/dev/null || true)"
      code="$(echo "$info" | tail -1)"; body="$(echo "$info" | head -n -1)"
      case "$code" in
        200) tk="あり・LINE に通りました（$(echo "$body" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log((j.displayName||"")+" "+(j.basicId||""))}catch(e){console.log("")}})')）" ;;
        401) tk="あり・LINE が受け付けません（トークンがちがう／失効。発行し直して入れ直してください）" ;;
        000) tk="あり・LINE に届きません（サーバーから api.line.me への通信が許可されていないかも）" ;;
        *)   tk="あり・LINE の返事 $code" ;;
      esac
    fi
    unset tok info body
    echo "   $tname"
    echo "     LINEで送る: $([ "$enabled" = "t" ] && echo 使う || echo '使わない（設定 → AI・送信 で「使う」に）')"
    echo "     チャネルシークレット: $sec"
    echo "     アクセストークン: $tk"
    echo "     LINE から最後に届いた: $last（友だち $seen 人、うちアプリとつながった $linked 人）"
    echo "     7日間の LINE 送信: 送れた $sent 件／失敗 $failed 件"
  done
}

reboot_hook() {  # サーバー再起動後に自分で立ち上がるように（crontab が使えるときだけ）
  local line="@reboot cd $(pwd) && ./node_modules/.bin/pm2 resurrect >/dev/null 2>&1"
  command -v crontab >/dev/null || { echo "   （crontab が無いので、再起動後は ./deploy.sh を実行してください）"; return 0; }
  if (crontab -l 2>/dev/null | grep -v "pm2 resurrect"; echo "$line") | crontab - 2>/dev/null; then
    echo "   再起動後の自動起動を crontab に登録しました"
  else
    echo "   （crontab が使えないので、再起動後は ./deploy.sh を実行してください）"
  fi
}

MODE="${1:-}"
if [ "$MODE" = "--auto" ]; then
  if [ "$(psql -X -tAc "select to_regclass('public.tenant') is not null" 2>/dev/null)" = "t" ] && $PM2 describe "$STORE-gateway" >/dev/null 2>&1; then
    MODE=""; echo "== 2回目以降の配備として進めます"
  else
    MODE="--init"; echo "== 初回の配備として進めます"
  fi
fi

case "$MODE" in
  --init)
    precheck_db
    echo "== DB の初期設定（役割・権限）"
    bash "$MIG" bootstrap
    [ "${DB_MODE:-}" = "single" ] || echo "== 内部の役割でログインできるか"
    [ "${DB_MODE:-}" = "single" ] || for pair in "authenticator:$AUTHENTICATOR_PASSWORD" "supabase_auth_admin:$AUTH_ADMIN_PASSWORD" "supabase_storage_admin:$STORAGE_ADMIN_PASSWORD"; do
      u="${pair%%:*}"; pw="${pair#*:}"
      if ! PGUSER="$u" PGPASSWORD="$pw" psql -X -tAc "select 1" >/dev/null 2>&1; then
        echo "!! $u で DB にログインできません。"
        echo "   同じ PostgreSQL に別の店舗が先に動いている場合、役割のパスワードは共有です。"
        echo "   最初の店舗の .env から AUTHENTICATOR_PASSWORD / AUTH_ADMIN_PASSWORD / STORAGE_ADMIN_PASSWORD を"
        echo "   この店舗の .env（GitHub なら Secrets）にコピーして、もう一度実行してください。"
        exit 1
      fi
    done
    echo "   OK"
    echo "== ファイル置き場の表"
    if [ "${DB_MODE:-}" = "single" ]; then
      sed -E 's/\b(anon|authenticated|service_role)\b/public/g; s/\bpublic(, *public)+/public/g' db/storage-schema.sql | psql -X -q -v ON_ERROR_STOP=1 -f -
    else
      PGUSER=supabase_storage_admin PGPASSWORD="$STORAGE_ADMIN_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 -f db/storage-schema.sql
    fi
    echo "== ログイン（GoTrue）を先に起動して、テーブルを作らせる"
    $PM2 start ecosystem.config.cjs --only "$STORE-auth" >/dev/null
    wait_http "http://127.0.0.1:${AUTH_PORT:-$(( ${LISTEN_PORT:-8032} + 30001 ))}/health" "ログイン"
    echo "== テーブル作成（2_データベース を全部）"
    bash "$MIG" schema
    echo "== 全部起動"
    $PM2 start ecosystem.config.cjs >/dev/null
    $PM2 save >/dev/null
    reboot_hook
    check
    ;;
  --sql)
    [ -n "${2:-}" ] || { echo "使い方: ./deploy.sh --sql ファイル名.sql"; exit 2; }
    bash "$MIG" schema "$2"
    ;;
  --status) $PM2 ls; check ;;
  --stop)   $PM2 delete "/^$STORE-/" >/dev/null 2>&1; $PM2 save --force >/dev/null 2>&1; echo "== $STORE を止めました" ;;
  "")
    echo "== 入れ替え"
    npm install --no-audit --no-fund --omit=dev 2>&1 | tail -1
    $PM2 startOrReload ecosystem.config.cjs >/dev/null
    $PM2 save >/dev/null
    check
    ;;
  *) sed -n '4,12p' "$0"; exit 2 ;;
esac
