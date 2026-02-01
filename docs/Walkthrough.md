# Walkthrough

## 概要

チケット管理の縦スライス（一覧 → 新規作成 → 詳細/更新）を実装し、開発用データの準備とテスト追加まで行いました。あわせて PostgreSQL 18 へのアップグレード内容も整理しています。

---

## 1. PostgreSQL 18 への更新（インフラ面）

- Docker/CI を PostgreSQL 18 に更新
  - `docker/postgres/Dockerfile` を `postgres:18-alpine` に変更
  - `.github/workflows/ci.yml` のサービスを 18 に変更
  - `docs/CI_CD.md` の記載更新
- データ移行（pg_upgrade）
  - 旧データを新ボリュームに移行
  - 新しいマウント先を `/var/lib/postgresql` に変更
- 認証強化
  - `pg_hba.conf` を `scram-sha-256` に変更
  - `password_encryption = 'scram-sha-256'` を設定
  - `postgres` パスワードを再ハッシュ
- 旧ボリュームを削除

---

## 2. チケット縦スライス実装

### ルーティング

- `/tickets` … 一覧
- `/tickets/new` … 新規作成
- `/tickets/:public_id` … 詳細 + 更新

### LiveView

- **一覧**: `TicketLive.Index`
  - stream でチケット表示
- **新規作成**: `TicketLive.New`
  - `AshPhoenix.Form` による作成フォーム
  - requester 必須のため、ユーザー 0 件時は作成ボタンを表示
- **詳細/更新**: `TicketLive.Show`
  - 表示とステータス/優先度更新フォーム

### データ準備

- `priv/repo/seeds.exs` にデフォルトユーザー作成（空の場合のみ）

### テスト

- LiveView テスト追加（一覧、作成、更新）

---

## 3. 動作確認

```bash
mix ecto.migrate
mix run priv/repo/seeds.exs
mix phx.server
```

---

## 2026-02-01 03:50 UTC

### チケットコメント機能（会話ログ）追加

- `ticket_messages` を追加（Ash リソース + マイグレーション）
- Ticket 詳細画面に「会話ログ」と「コメント追加」フォームを実装
- コメント追加時に `tickets.latest_message_at` を更新
- LiveView テストを拡張（コメント追加の検証）
- `mix precommit` で検証（9 tests / 0 failures）
