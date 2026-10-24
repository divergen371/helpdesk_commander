# 🚀 クイックスタートガイド

## 前提バージョン

リポジトリの `.tool-versions` に固定しています。

- Erlang/OTP **29.1.2**
- Elixir **ref:v1.20.4**
- PostgreSQL 18（Docker Compose）

```bash
asdf install
```

## 現在の実装状況（2026-10-24）

- Phoenix + Ash 基盤
- コアリソース: `Accounts.User` / `Helpdesk.Ticket` / `Tasks.Task`
- ID方針: `bigint` 連番PK + `public_id`（**tickets/tasksのみ**）
- 初期マイグレーション: `priv/repo/migrations/20260131061820_init_core_resources.exs`
- CI: GitHub Actions（詳細は `docs/CI_CD.md`）
- 現状・残タスク: `docs/STATUS.md` / `docs/ROADMAP.md` / `docs/TASKS.md`

## 📦 セットアップ

### 1. まとめて実行

```bash
make setup
```

### 2. 手動で実行

```bash
mix deps.get
make docker-up
make db-create
make db-migrate
```

> **DB名に注意**  
> `config/dev.exs` のデフォルトは `helpdesk_commander_dev` です。  
> Docker側は `POSTGRES_DB` のデフォルトが `postgres` なので、`.env`（`.env.example`）で合わせるか `DATABASE_NAME` を設定してください。

## 🛠 よく使うコマンド

```bash
# サーバー起動
make server

# データベース操作
make db-create     # DB作成
make db-migrate    # マイグレーション実行
make db-reset      # DBリセット
make db-seed       # シードデータ投入

# Docker操作
make docker-up     # PostgreSQL起動
make docker-down   # PostgreSQL停止
make docker-logs   # ログ確認

# 開発
make test          # テスト実行
make format        # コードフォーマット
make credo         # コード品質チェック
make dialyzer      # 型チェック（必要なら make dialyzer-plt）

# まとめてチェック
mix precommit
```

## 🔍 動作確認

### 1. サーバー起動

```bash
make server
```

### 2. ブラウザでアクセス

- メインページ: http://localhost:4000
- LiveDashboard: http://localhost:4000/dev/dashboard
- メールボックス: http://localhost:4000/dev/mailbox

## 🎯 次のステップ

- `public_id` を使ったチケット/タスクのUI（LiveView）実装  
  - 例: `/tickets/:public_id`
- 認証（AshAuthentication）導入
- 追加リソース（inquiries / conversations / events など）
- 変更したら `docs/DB_SCHEMA.md`・`docs/ERD.md` を更新

## 📚 参考ドキュメント

- `docs/REQUIREMENTS.md`
- `docs/DB_SCHEMA.md`
- `docs/ERD.md`
- `docs/SEQUENCE.md`
- `docs/BRANCH_STRATEGY.md`
- `docs/CI_CD.md`

---

詳細は `README.md` を参照してください。
