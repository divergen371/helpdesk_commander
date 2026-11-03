# バックアップ / 復元・鍵運用手順 — HC-10

PostgreSQL のバックアップ / 復元と、`CLOAK_KEY`・`PII_HMAC_SECRET`・
`COMPANY_CODE_HMAC_SECRET` の保管・ローテーション方針。

## 1. バックアップ

対象は 2 系統ある。

1. **PostgreSQL（データ本体）**: `pg_dump` のカスタム形式（`-Fc`、圧縮付き）
2. **添付ファイル（`ATTACHMENTS_ROOT`）**: DB 外のディスク保存。DB と同じ頻度で
   ディレクトリを丸ごと rsync / スナップショットする（DB の行だけでは復元できない）

### 1.1 取得

```bash
# コンテナ稼働のローカル / ステージング想定。本番は DB クライアントから直接実行
docker exec helpdesk_commander_postgres \
  pg_dump -U postgres -Fc helpdesk_commander_prod > backup_20260101.dump
```

- 実行頻度は日次（cron の例: `5 3 * * *`、失敗時はアラート）
- ダンプは **DB サーバー外に 3 世代以上**保管する（S3 / 別ホスト）。
  RPO = 24 時間、RTO（復元 + アプリ起動）は 30 分を想定
- `pg_dump` は排出時点の一貫性を持つ。コールドバックアップと重複させない

## 2. 復元

```bash
createdb -U postgres helpdesk_commander_prod_restored

pg_restore -U postgres --no-owner -d helpdesk_commander_prod_restored backup_20260101.dump
ANALYZE;
```

注意:

- `--no-owner` は Docker ローカル環境の所有者不一致を回避する。本番では
  権限設計に合わせて `--no-privileges` の要否を決める
- `Oban` のジョブ行も一緒に復元される。アプリ起動は自動で再接続

## 3. 復元演習（ステージング）

本番（本番鍵相当）ダンプをステージングに流して検証する演習を四半期に 1 回実施する。
手順は 2 節のとおり。その後、復号検証スクリプトを実行する:

```bash
DATABASE_URL=postgres://postgres:localhost:5433/helpdesk_commander_prod_restored \
  mix run priv/verify/verify_restore.exs
```

検証内容（`priv/verify/verify_restore.exs`）:

- `companies` / `users` の cloak 属性（会社名・email・display_name）が
  **`CLOAK_KEY` で復号できる**
- 復号した値から計算した HMAC が `name_hash` / `email_hash` と一致する
  （= `PII_HMAC_SECRET` が同じである）

スクリプトはメールと会社名を標準出力に出すので、本番データを扱う場合は
閲覧許可のある環境で実行する。

## 4. 鍵の保管とローテーション

| 変数 | 用途 | 保管 |
| --- | --- | --- |
| `CLOAK_KEY` | cloak された PII（users.email / display_name、companies.name など）の復号 | シークレットマネージャ、または Git 管理外の 0600 `.env` |
| `PII_HMAC_SECRET` | `users.email_hash` / `companies.name_hash` の HMAC | 同上 |
| `COMPANY_CODE_HMAC_SECRET` | `companies.company_code_hash` の HMAC | 同上 |

- 鍵はソース管理に入れない。`.gitignore` に `.env` が登録済みか運用側で確認し、
  `.env` は chmod 0600 で保持する
- 鍵の紛失 = 該当データ全体の復号不能。シークレットマネージャと
  オフライン（紙 / 隔離端末）の 2 系統以上でバックアップする

### 4.1 `CLOAK_KEY` のローテーション

cloak は複数 cipher を同時に保持できる（tag で切り替え）。手順:

1. 新鍵を発行する（`openssl rand -base64 32`）。
2. `config/runtime.exs` の `ciphers` を **新鍵 default・旧鍵 retired** にする:

   ```elixir
   config :helpdesk_commander, HelpdeskCommander.Vault,
     ciphers: [
       default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V2", key: Base.decode64!(new_key)},
       retired: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(old_key)}
     ]
   ```

   書き込みは新鍵、読み出しは tag に応じた鍵で自動選択される
3. cloak 属性を持つリソース（users・companies・incidents など）を全件
   `Ash.update` で再書き込みし、全行を新鍵に暗号化し直す
4. 新鍵化の完了後、旧 cipher を設定から外す前に 3 節の検証で
   「復号失敗 0 件」を確認する（旧鍵でしか読めない行が残っていないか）
5. 頻度は年 1 回。鍵漏えいの疑いがあるときは随時

### 4.2 `PII_HMAC_SECRET` / `COMPANY_CODE_HMAC_SECRET` のローテーション

HMAC は一方向のため、回転は「復号した平文から再ハッシュ」となる:

1. 新 secret を用意して運用環境に適用したあと、
   `users`・`companies` を `Ash.update`（email_hash / name_hash の再計算変更を通す
   `update` アクション経由）で全件処理し、ハッシュを作り直す
2. 処理終了後、旧 secret は破棄する
3. 頻度は年 1 回、またはインシデント時。secret を差し替えた直後は
   再計算済みの行だけが照合に成功するため、メンテナンスウィンドウで
   全件完了までまとめて実施する

### 4.3 変更後の確認

`priv/verify/verify_restore.exs` は復元のほかに、**cloak 復号と HMAC の整合を
一括で確認する道具**としてローテーション後の検証にも使える。

---

## 演習実績

- 本タスクで **ローカル（dev DB・dev 鍵）** で同一手順の演習を実施した:
  `pg_dump -Fc` → `createdb` + `pg_restore` → 検証スクリプトで
  会社 1 件・ユーザー 3 件がすべて ok（会社名・email・display_name の復号および
  HMAC 一致を確認）
- ステージングでの本鍵演習は本手順 3 節にしたがい、四半期の運用サイクルで実施する
