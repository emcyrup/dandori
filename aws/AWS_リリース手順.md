# ナイトだんどり　AWS リリース手順

## 構成

| 部品 | これまで | AWS版 |
|---|---|---|
| 1_画面 | Netlify にドラッグ | **S3 + CloudFront**（`aws/template.yaml`） |
| 2_データベース | Supabase | Supabase（変更なし） |
| 3_サーバー | Supabase Edge Functions | Supabase（変更なし） |

画面のコードは1行も変えていません。`config.js` の接続先もそのままです。
Netlify の `_headers`（毎回最新を確認）は CloudFront のレスポンスヘッダーで同じ動きにしています。

---

## 0. 事前に用意するもの

- AWS アカウントと、管理者権限のある AWS CLI（`aws configure` 済み）
- 独自ドメインを使う場合のみ：ACM 証明書（**us-east-1 / バージニア北部** で発行）

## 1. 土台をつくる（初回だけ・約5〜10分）

```bash
aws cloudformation deploy \
  --region ap-northeast-1 \
  --stack-name dandori-night \
  --template-file aws/template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
      GitHubRepo=emcyrup/dandori \
      CreateGitHubOidcProvider=true
```

- 独自ドメインを使うときは `DomainName=night.example.jp AcmCertificateArn=arn:aws:acm:us-east-1:...` を足す
- GitHub の自動デプロイを使わないなら `GitHubRepo` 以降は不要
- アカウントに GitHub の OIDC プロバイダが既にあれば `CreateGitHubOidcProvider=false`

できあがったら、出力を確認します。

```bash
aws cloudformation describe-stacks --region ap-northeast-1 --stack-name dandori-night \
  --query "Stacks[0].Outputs" --output table
```

## 2. 画面を配る

```bash
./aws/deploy.sh dandori-night
```

文法チェック（`node --check`）→ S3 へ同期 → キャッシュ削除 まで自動でやります。
最後に表示される URL（`https://xxxx.cloudfront.net/`）が新しい入口です。

### 自動デプロイ（任意）

GitHub リポジトリの Settings → Secrets and variables → Actions → **Variables** に登録すると、
`main` に画面の変更が入るたびに自動で配られます。

| 名前 | 値 |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | 手順1の出力 `DeployRoleArn` |
| `AWS_REGION` | `ap-northeast-1`（省略可） |
| `AWS_STACK_NAME` | `dandori-night`（省略可） |

## 3. Supabase 側の設定変更（★忘れるとログインまわりが動きません）

アドレスが Netlify から変わるので、Supabase に新しいアドレスを教えます。

1. **Authentication → URL Configuration**
   - **Site URL** を新しいアドレスに（例 `https://xxxx.cloudfront.net`）
   - **Redirect URLs** に `https://xxxx.cloudfront.net/**` を追加
     （パスワード再設定メールの戻り先 `reset.html` がここで許可されます）
   - 切り替え期間は、Netlify のアドレスも残しておくと安全です

2. **シフト希望の本人用リンク**（`store.wish_base_url` を入れている場合のみ）

   ```sql
   update public.store
      set wish_base_url = 'https://xxxx.cloudfront.net/'
    where wish_base_url like '%netlify%';
   ```
   空のままのお店は、画面側で今のアドレスを自動で使うので対応不要です。

3. **未実行の SQL**（README のとおり、AWS とは関係なくまだ必要）
   `2_データベース/だんどり共通_017-027.sql` を実行 → `select * from app.demo_fill_all();`

LINE の Webhook・Edge Functions・AI の鍵は Supabase に置いたままなので、変更不要です。

## 4. 独自ドメイン（任意）

DNS に CNAME を1つ追加します（Route 53 なら ALIAS）。

```
night.example.jp.  CNAME  xxxx.cloudfront.net.
```

## 5. 切り替え前チェックリスト

- [ ] 新しい URL で `login.html` からログインできる
- [ ] スタッフログイン（staff-login）が通る
- [ ] パスワード再設定メールのリンクが新しいアドレスの `reset.html` に戻る
- [ ] ホール画面の自動更新・締めの AI 下書きが動く
- [ ] シフト希望の本人用リンクが新しいアドレスになっている
- [ ] 古いタブレット / iPhone で表示できる
- [ ] 問題なければ Netlify を停止し、Supabase の Redirect URLs から Netlify を外す

## 戻し方

Netlify を止めるまでは、旧アドレスを案内するだけで元に戻せます。
AWS 側を消すときは `aws cloudformation delete-stack --stack-name dandori-night`
（S3 バケットは消えずに残る設定です。中身を空にしてから手で削除してください）。

## 費用の目安

小規模店舗の利用（月数GB程度の転送）なら、S3 + CloudFront は **月数十円〜数百円** 程度です。
CloudFront の無料枠（月1TB転送）に収まることがほとんどです。
