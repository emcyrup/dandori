# ナイトだんどり　AWS 移行・リリース手順

Supabase に置いていたもの（データベース・ログイン・ファイル・サーバー処理）を、すべて AWS にまとめます。
画面・SQL・サーバー処理のコードは、ほぼそのまま使います（Supabase と同じ部品を AWS の上で動かす方式）。

## 構成

```
 ブラウザ / LINE
     │  https://（1つのアドレス）
     ▼
 CloudFront ──────────────┬─ /            → S3（1_画面）
                          └─ /rest/v1/    ┐
                             /auth/v1/    │ VPC 内の ALB（インターネットから直接は届かない）
                             /storage/v1/ │   ↓
                             /functions/v1/┘ ECS Fargate（1つのタスクに5つの部品）
                                              ├ gateway    入口（nginx）
                                              ├ rest       データの受け口（PostgREST）
                                              ├ auth       ログイン（GoTrue）
                                              ├ storage    ファイル → S3
                                              └ functions  3_サーバー をそのまま実行
                                                   ↓
                                              RDS PostgreSQL 17（非公開）
 EventBridge ─ 5分ごと ─→ /functions/v1/send-outbox（pg_cron の代わり）
```

| Supabase で | AWS では |
|---|---|
| Database | RDS PostgreSQL 17 |
| Auth | GoTrue（Supabase と同じもの）on ECS |
| PostgREST（`sb.rpc` / `sb.from`） | PostgREST on ECS |
| Storage | storage-api on ECS → S3 |
| Edge Functions | edge-runtime on ECS（`3_サーバー` をそのまま） |
| Functions の Secrets | Secrets Manager |
| pg_cron + pg_net | EventBridge（5分ごと） |
| SQL Editor | `./aws/run-migrator.sh` |
| Netlify | S3 + CloudFront |

### Supabase との違い（知っておくこと）

- **service_role の扱い**：RDS では「RLS を素通りする権限（BYPASSRLS）」が付けられません。
  そのかわり、SQL を流すたびに `aws/migrator/post.sql` が
  「service_role は全件 OK」のポリシーを全テーブルに足します。
  `run-migrator.sh schema` を使えば自動で流れます。**SQL を流したら必ず post.sql まで流すこと。**
- **管理画面（Supabase Studio）はありません**。SQL は `run-migrator.sh sql "…"` で流します。
- **鍵（anon / service_role）が変わります**。切り替え後は、全員いちど**ログインし直し**になります。
  パスワードはそのまま移るので、同じパスワードで入れます。

### この構成で確かめたこと

RDS と同じ権限の制約（マスターユーザーは superuser ではない）にした PostgreSQL 17 の上で、
本番と同じコンテナを組み合わせて、次のことを確かめています。

- 初期設定 → GoTrue のテーブル作成（70件）→ Storage のテーブル作成 → `2_データベース` 全部 → デモデータ
- 店長のログイン、自分のお店だけ見える（RLS）、未ログインでは読めない、`tenant_secret` は店長でも読めない
- 書類のアップロード・署名付き URL、ほかの法人のフォルダには書けない
- `staff-login` でスタッフのログインを作り、そのスタッフでログインできる
- `ai` / `send-outbox` / `line-webhook` / `photo-search` が動く（`line-webhook` はログインの鍵なしで届く）
- 移行（`import`）：51テーブル・559行がすべて一致、ファイルの写し（`copy-storage.mjs`）
- 実際の画面（伝票・書類・売上・給与・清掃・管理）がブラウザでエラーなく表示される

まだ確かめていないのは、**本物の AWS の上での動作**（S3・SES・CloudFront の VPC オリジンなど）です。
本番の前に、下の手順で一度「練習用」の環境を作って確認してください。

---

## 0. 用意するもの

- AWS アカウント、AWS CLI（管理者権限で `aws configure` 済み）
- Docker、Node.js 18 以上
- メール送信用：Amazon SES で送信元アドレス（またはドメイン）を認証し、本番利用の申請をしておく
- 独自ドメインを使う場合：ACM 証明書（**us-east-1 / バージニア北部** で発行）

以下、スタック名は `dandori-night`、リージョンは東京（`ap-northeast-1`）の例です。

```bash
export STACK=dandori-night AWS_REGION=ap-northeast-1
```

## 1. 土台をつくる（約20分。RDS の作成に時間がかかります）

```bash
aws cloudformation deploy \
  --stack-name $STACK \
  --template-file aws/template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
      DesiredCount=0 \
      SmtpAdminEmail=noreply@example.jp \
      GitHubRepo=emcyrup/dandori
```

- この時点では API サーバーは **0台**（まだコンテナが無いため）
- 独自ドメインを使うときは `DomainName=night.example.jp AcmCertificateArn=arn:aws:acm:us-east-1:...` を足す
- GitHub の自動デプロイを使わないなら `GitHubRepo` は不要

## 2. コンテナを作って入れる

```bash
./aws/build-images.sh
```

## 3. 鍵を入れる（Secrets Manager）

スタックの出力に、入れる場所（ARN）が出ています。

```bash
aws cloudformation describe-stacks --stack-name $STACK --query "Stacks[0].Outputs" --output table
```

| 出力名 | 入れるもの |
|---|---|
| `AppSecretsArn` | AI と写真検索の鍵（使うものだけ。Supabase の Functions Secrets と同じ値） |
| `SmtpSecretArn` | SES の SMTP ユーザー名・パスワード（SES → SMTP settings → Create SMTP credentials） |

```bash
aws secretsmanager put-secret-value --secret-id <AppSecretsArn> --secret-string \
  '{"ANTHROPIC_API_KEY":"sk-ant-...","GEMINI_API_KEY":"","OPENAI_API_KEY":"","PIXABAY_API_KEY":"..."}'

aws secretsmanager put-secret-value --secret-id <SmtpSecretArn> --secret-string \
  '{"username":"AKIA...","password":"..."}'
```

※ 鍵はターミナルの履歴に残ります。気になる場合は AWS コンソールの Secrets Manager から入れてください。

## 4. データベースの初期設定 → API サーバーを起動

```bash
./aws/run-migrator.sh bootstrap          # 役割・権限（Supabase に最初からあるもの）を作る

aws cloudformation deploy --stack-name $STACK --template-file aws/template.yaml \
  --capabilities CAPABILITY_IAM --parameter-overrides DesiredCount=1 \
  SmtpAdminEmail=noreply@example.jp GitHubRepo=emcyrup/dandori
```

起動すると、ログイン（GoTrue）とファイル（Storage）が、自分のテーブルを RDS に作ります。

## 5. テーブルを作る

```bash
./aws/run-migrator.sh schema             # 2_データベース を番号順に全部 → post.sql
```

ここから先は、**新しく始める**か**Supabase から移す**かで分かれます。

### 5-A. 新しく始める（デモ・新規のお店）

```bash
./aws/run-migrator.sh demo               # デモデータ（select * from app.demo_fill_all()）
```

最初の店長のログインを作ります（Supabase の「Add user」の代わり）。

```bash
URL=$(aws cloudformation describe-stacks --stack-name $STACK --query "Stacks[0].Outputs[?OutputKey=='SiteUrl'].OutputValue" --output text)
SVC=$(aws secretsmanager get-secret-value --secret-id <ApiKeysSecretArn> --query SecretString --output text | node -pe 'JSON.parse(require("fs").readFileSync(0)).service_role_key')

curl -X POST "$URL/auth/v1/admin/users" -H "Authorization: Bearer $SVC" -H "apikey: $SVC" \
  -H 'Content-Type: application/json' \
  -d '{"email":"owner@example.jp","password":"（初期パスワード）","email_confirm":true}'

./aws/run-migrator.sh sql "select name, role from app.link_staff('owner@example.jp', '鈴木', 'owner')"
```

### 5-B. Supabase から移す（本番データ）

1. **移行元の接続文字列を入れる**
   Supabase → Project Settings → Database → Connection string → **Session pooler**（IPv4 で繋がるもの）
   ```bash
   aws secretsmanager put-secret-value --secret-id <SourceDbSecretArn> \
     --secret-string '{"url":"postgresql://postgres.mfsvfolyrkrpribnwvcl:（DBパスワード）@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres"}'
   ```
2. **移行中は Supabase 側の入力を止める**（お店に「◯時〜◯時は入力しないでください」と連絡）
3. **データを移す**（ログインのユーザーとパスワード、public / app の全データ）
   ```bash
   ./aws/run-migrator.sh import
   ```
   ※ 先に `schema` で入ったデモデータは消してから入れます。最後に件数を表示します。
4. **ファイルを移す**（書類・背景写真・取込ファイル）
   ```bash
   SRC_URL=https://mfsvfolyrkrpribnwvcl.supabase.co SRC_KEY=<Supabase の service_role キー> \
   DST_URL=$URL DST_KEY=$SVC \
   node aws/tools/copy-storage.mjs
   ```
5. **移行元の接続文字列を消す**
   ```bash
   aws secretsmanager put-secret-value --secret-id <SourceDbSecretArn> --secret-string '{"url":""}'
   ```

## 6. 画面を配る

```bash
./aws/deploy.sh
```

`config.js` の接続先を **AWS 版に差し替えた写し**を配ります（リポジトリの `config.js` は Supabase のまま）。
最後に表示される URL が新しい入口です。

## 7. 外のサービスの設定を変える

- **LINE Developers** → Messaging API → Webhook URL（法人ごと）
  ```
  https://（新しいアドレス）/functions/v1/line-webhook?t=（法人ID）
  ```
- **シフト希望の本人用リンク**（`store.wish_base_url` を入れている場合のみ）
  ```bash
  ./aws/run-migrator.sh sql "update public.store set wish_base_url = '$URL/' where wish_base_url like '%netlify%'"
  ```
- **送信箱の定期送信**を使うなら、スタックを `OutboxSchedule=ENABLED` で更新

## 8. 切り替え前チェックリスト

- [ ] `login.html` から店長・スタッフがログインできる（移行した場合は、前と同じパスワードで）
- [ ] 伝票・売上・給与など、移したデータが前と同じに見える
- [ ] 書類の「控え」が開ける（ファイルが移っている）
- [ ] パスワード再設定メールが届き、リンクから `reset.html` に戻れる
- [ ] 管理 → ログインの管理 で、スタッフのログインを作れる（staff-login）
- [ ] 締めの AI 下書きが出る
- [ ] LINE で「10/1 10-17」のように送ると、シフト希望に入る
- [ ] 古いタブレット / iPhone で表示できる
- [ ] 問題なければ、Netlify と Supabase を止める（Supabase はしばらく一時停止で残しておくと安心）

---

## ふだんの運用

| やりたいこと | コマンド |
|---|---|
| 画面を直した | `./aws/deploy.sh` |
| 3_サーバー を直した | `./aws/build-images.sh`（API サーバーの入れ替えまで自動） |
| SQL を足した | `./aws/build-images.sh` → `./aws/run-migrator.sh schema 新しいファイル.sql` |
| SQL を1文流したい | `./aws/run-migrator.sh sql "select ..."` |
| ログを見たい | `aws logs tail /dandori/$STACK --follow` |
| バックアップ | RDS が毎日自動（7日分）。消すときもスナップショットが残る設定 |

GitHub Actions の Variables に `AWS_DEPLOY_ROLE_ARN`（手順1の出力 `DeployRoleArn`）を入れると、
`main` に入った変更は、画面・コンテナとも自動で配られます（SQL は自動では流しません）。

## 費用の目安（東京リージョン、月額・概算）

| もの | 目安 |
|---|---|
| ECS Fargate（1 vCPU / 2GB × 1台） | 約 $45 |
| RDS db.t4g.micro + 20GB | 約 $22 |
| ALB | 約 $18 |
| Secrets Manager（9個）・公開 IP・ログ | 約 $8 |
| S3 / CloudFront | ほぼ無料枠内 |
| **合計** | **約 $90（1万3千円前後）** |

Supabase Pro（$25）より高くなります。そのかわり、データも鍵もすべて自社の AWS アカウントの中に入ります。
お店が増えても、この構成のまま数十店舗程度までは台数を増やさずに動く見込みです。
RDS を2か所に置く（`DbMultiAZ=true`）と、RDS の費用はおよそ倍になります。

## 困ったとき

- **API が 502 / 503**：`aws logs tail /dandori/$STACK --since 30m` で、どの部品が止まっているか確認
- **SQL を足したのに「関数が見つからない」**：
  `./aws/run-migrator.sh sql "notify pgrst, 'reload schema'"` で PostgREST に読み直させる
- **サーバー処理だけ 401**：`NO_VERIFY_JWT` に入っていない関数は、ログインの鍵が必要です
- **AI の下書きが途中で切れる**：CloudFront の待ち時間は 60 秒です。それより長い場合は
  AWS サポートに上限緩和（最大 180 秒）を申請し、`template.yaml` の `OriginReadTimeout` を上げます
