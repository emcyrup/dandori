# stores/ — 店舗ごとの設定

1店舗 = 1フォルダです。フォルダ名が「店舗名（半角英数）」で、`.env` の `STORE` と GitHub の Environment 名に一致させます。

```
stores/
  olivia/
    store.sql     お店・メニュー・キャスト・給与の設定（この店舗だけ）
```

- `2_データベース/`（全店共通）を流したあとに、`stores/<店舗>/*.sql` が名前順で流れます。
- 店舗の SQL は、何度流しても二重にならないように書きます（`olivia/store.sql` を手本に）。

## 新しい店舗を増やす手順

1. **このフォルダ**：`stores/olivia/` をコピーして `stores/<新店舗>/` を作り、`store.sql` の
   お店の名前・メニュー・キャスト・バック率・時給を書き換える。
2. **サーバー**：提供元に、その店舗用の DB（例 `dandori<新店舗>`）とサブドメイン・ポートを発行してもらう。
   同じサーバーに置く場合も別のサーバーでもよい（別フォルダ `~/dandori-<新店舗>` に入る）。
3. **GitHub**：Settings → Environments → New environment で `<新店舗>` を作り、
   - Secrets：`SERVER_SSH_KEY` `DB_PASSWORD`（必要なら SMTP・AI の鍵）
   - Variables：`SERVER_HOST` `SERVER_USER` `SERVER_DIR` `SITE_URL` `LISTEN_PORT` `DB_NAME`
4. **リポジトリの Variables**：`STORES` に店舗名をカンマ区切りで足す（例 `olivia,second`）。
5. `main` に push すると、`STORES` の店舗が順に配備されます。
   1店舗だけ配備したいときは Actions → deploy-server → Run workflow で店舗名を入れます。

同じサーバーに複数店舗を置くときは、`LISTEN_PORT` を店舗ごとに変えるだけで、
中の部品のポートと PM2 のプロセス名（`<店舗>-gateway` など）は自動で分かれます。
