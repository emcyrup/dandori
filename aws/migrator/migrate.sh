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
SQL_DIR="${SQL_DIR:-/work/sql}"          # 全店共通の SQL（2_データベース）
STORE_SQL_DIR="${STORE_SQL_DIR:-}"       # その店舗だけの SQL（stores/<店舗>/）。空なら無し
HERE="$(cd "$(dirname "$0")" && pwd)"
export PGDATABASE="${PGDATABASE:-postgres}"
export PGSSLMODE="${PGSSLMODE:-require}"
PSQL="psql -X -v ON_ERROR_STOP=1 --no-psqlrc"
export PGAPPNAME="${PGAPPNAME:-dandori_fn}"   # SQL の中のデータ投入が RLS で止まらないように（単一ロールモード用）
DB_MODE="${DB_MODE:-roles}"               # roles（Supabase と同じ役割あり）/ single（DB ユーザー1つだけ）

# 単一ロールモードでは、SQL の中の役割名（anon / authenticated / service_role）を public に読み替える。
# 役割名は grant / revoke / create policy にしか出てこないことを確認済み（データとしては使っていない）。
run_sql_file() {
  if [ "$DB_MODE" = "single" ]; then
    sed -E 's/\b(anon|authenticated|service_role)\b/public/g; s/\bpublic(, *public)+/public/g' "$1" | $PSQL -q -f -
  else
    $PSQL -q -f "$1"
  fi
}

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
  if [ "$DB_MODE" = "single" ]; then
    echo "== 下ごしらえ (pre-single.sql)"
    $PSQL -q -f "$HERE/pre-single.sql"
  fi
  for f in "$@"; do
    echo "== $(basename "$f")"
    run_sql_file "$f"
  done
  if [ "$DB_MODE" = "single" ]; then
    echo "== 仕上げ (post-single.sql)"
    $PSQL -q -f "$HERE/post-single.sql"
  else
    echo "== 仕上げ (post.sql)"
    $PSQL -q -f "$HERE/post.sql"
  fi
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  bootstrap)
    if [ "$DB_MODE" = "single" ]; then
      $PSQL -q -f "$HERE/bootstrap-single.sql"; echo "== bootstrap（単一ロール）完了"; exit 0
    fi
    $PSQL -q \
      -v authenticator_pw="$AUTHENTICATOR_PASSWORD" \
      -v auth_admin_pw="$AUTH_ADMIN_PASSWORD" \
      -v storage_admin_pw="$STORAGE_ADMIN_PASSWORD" \
      -f "$HERE/bootstrap.sql"
    echo "== bootstrap 完了"
    ;;

  schema)
    if [ $# -gt 0 ]; then
      # 名前で指定：共通 → 店舗 の順にさがす
      set -- $(for n in "$@"; do
                 if [ -f "$SQL_DIR/$n" ]; then echo "$SQL_DIR/$n";
                 elif [ -n "$STORE_SQL_DIR" ] && [ -f "$STORE_SQL_DIR/$n" ]; then echo "$STORE_SQL_DIR/$n";
                 else echo "!! $n が見つかりません" >&2; exit 2; fi
               done)
    else
      # 名前にある最初の3桁の番号の順（001…016 → だんどり共通_017-027 → 028…）
      set -- $(for f in "$SQL_DIR"/*.sql; do
                 n=$(basename "$f" | grep -oE '[0-9]{3}' | head -1); echo "${n:-999} $f"
               done | sort -n | awk '{print $2}') \
             $( [ -n "$STORE_SQL_DIR" ] && ls "$STORE_SQL_DIR"/*.sql 2>/dev/null | sort )
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
    # 書き込み先が PostgreSQL 16 以下でも通るように（17 からの設定項目を外す）
    sed -i '/^SET transaction_timeout/d' $DUMP/auth.sql $DUMP/app.sql
    if ! $PSQL -qc "set session_replication_role = replica" >/dev/null 2>&1; then
      echo "!! $PGUSER に session_replication_role を変える権限がありません。"
      echo "   superuser で次を1回流してください（PostgreSQL 15 以上）:"
      echo "   grant set on parameter session_replication_role to $PGUSER;"
      exit 1
    fi
    echo "== 書き込み（いま入っているデモデータは消します）"
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
    if [ "$DB_MODE" = "single" ]; then $PSQL -q -f "$HERE/post-single.sql"; else $PSQL -q -f "$HERE/post.sql"; fi
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
