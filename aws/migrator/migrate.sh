#!/bin/sh
# ============================================================================
#  ナイトだんどり / データベース係（ECS の使い捨てタスクとして動きます）
#
#  使い方（aws/run-migrator.sh から呼ばれます）
#    bootstrap        役割・権限の初期設定（最初に1回）
#    schema           2_データベース の SQL を番号順に全部流す → 仕上げ(post.sql)
#    schema FILE...   指定した SQL だけ流す → 仕上げ
#    import           Supabase から本番データを移す（SOURCE_DB_URL が必要）
#    demo             デモデータを入れる（app.demo_fill_all）
#    sql "文"         SQL を1文だけ実行する
#
#  接続先は PGHOST / PGUSER / PGPASSWORD（RDS マスター）で受け取ります。
# ============================================================================
set -eu
SQL_DIR="${SQL_DIR:-/work/sql}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PGDATABASE="${PGDATABASE:-postgres}"
export PGSSLMODE="${PGSSLMODE:-require}"
PSQL="psql -X -v ON_ERROR_STOP=1 --no-psqlrc"

wait_for() {  # GoTrue / Storage が自分の表を作り終えるのを待つ
  i=0
  until [ "$($PSQL -tAc "select to_regclass('$1') is not null")" = "t" ]; do
    i=$((i + 1)); [ $i -gt 60 ] && { echo "!! $1 ができていません（ECS サービスは動いていますか）"; exit 1; }
    echo "   $1 を待っています..."; sleep 5
  done
}

run_files() {
  wait_for auth.users
  wait_for storage.buckets
  for f in "$@"; do
    echo "== $(basename "$f")"
    $PSQL -q -f "$f"
  done
  echo "== 仕上げ (post.sql)"
  $PSQL -q -f "$HERE/post.sql"
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  bootstrap)
    $PSQL -q \
      -v authenticator_pw="$AUTHENTICATOR_PASSWORD" \
      -v auth_admin_pw="$AUTH_ADMIN_PASSWORD" \
      -v storage_admin_pw="$STORAGE_ADMIN_PASSWORD" \
      -f "$HERE/bootstrap.sql"
    echo "== bootstrap 完了"
    ;;

  schema)
    if [ $# -gt 0 ]; then
      set -- $(for n in "$@"; do echo "$SQL_DIR/$n"; done)
    else
      # 001〜016 を番号順に、最後に だんどり共通_017-027.sql
      set -- $(ls "$SQL_DIR"/[0-9][0-9][0-9]_*.sql | sort) "$SQL_DIR"/だんどり共通_*.sql
    fi
    run_files "$@"
    echo "== schema 完了"
    ;;

  import)
    : "${SOURCE_DB_URL:?SOURCE_DB_URL（Supabase の接続文字列）が空です}"
    DUMP=/tmp/dump; mkdir -p $DUMP
    echo "== Supabase から読み出し"
    pg_dump "$SOURCE_DB_URL" --data-only --no-owner --no-privileges \
      -t auth.users -t auth.identities -f $DUMP/auth.sql
    pg_dump "$SOURCE_DB_URL" --data-only --no-owner --no-privileges \
      -n public -n app -f $DUMP/app.sql
    echo "== RDS へ書き込み（いま入っているデモデータは消します）"
    $PSQL -q <<SQL
begin;
set session_replication_role = replica;
do \$\$
declare r record;
begin
  for r in select schemaname, tablename from pg_tables where schemaname in ('public', 'app') loop
    execute format('truncate table %I.%I cascade', r.schemaname, r.tablename);
  end loop;
end \$\$;
truncate table auth.identities, auth.users cascade;
\i $DUMP/auth.sql
\i $DUMP/app.sql
commit;
SQL
    $PSQL -q -f "$HERE/post.sql"
    echo "== 件数の確認"
    $PSQL -c "select (select count(*) from auth.users) as users, (select count(*) from public.tenant) as tenants, (select count(*) from public.store) as stores"
    echo "== import 完了（ファイルは aws/tools/copy-storage.mjs で別に移します）"
    ;;

  demo)
    $PSQL -c "select * from app.demo_fill_all();"
    ;;

  sql)
    $PSQL -c "$1"
    ;;

  *)
    sed -n '2,14p' "$0"; exit 2 ;;
esac
