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

---

## 2026-02-01 04:20 UTC

### プロパティベーステスト準備

- `stream_data` を依存に追加（Ash依存の関係で `:only` 指定なし）
- `HelpdeskCommander.PropertyCase` を追加（`ExUnitProperties` と `StreamData` を共通import）

---

## 2026-02-01 04:26 UTC

### PropEr 導入

- `proper` を `:test` 依存に追加

---

## 2026-02-01 04:28 UTC

### PropEr プロパティテスト実行

- `test/support/proper_public_id.erl` を追加（PropEr の property 定義）
- `test/helpdesk_commander/support/public_id_proper_test.exs` で `:proper.quickcheck/2` を実行
- `erlc_paths` を追加して `test/support` の `.erl` をテスト時にコンパイル
- `mix test test/helpdesk_commander/support/public_id_proper_test.exs` 実行（PropEr 100ケース成功）
- `mix precommit` 実行（PropEr 100ケース + 既存テスト通過）

---

## 2026-02-01 06:00 UTC

### タスク優先度の履歴（task_events）下地追加

- `Tasks.TaskEvent` リソースを追加（`task_events` テーブル）
- `Tasks.Task` に `set_priority` アクションを追加し、優先度変更時に `task_events` を記録
- DBへ反映するなら `mix ecto.migrate`
- タスクCRUD UIを作るときに、優先度変更は `update :set_priority` を使う
- `mix precommit` 実行（10 tests / 0 failures）

---

## 2026-02-01 06:13 UTC

### task_events.actor_id の方針見直し（null禁止）

- 監査性のため、`task_events.actor_id` は null を許容しない方針に変更
- システム操作は system user（`system@helpdesk.local`）を actor として記録
- 既存nullを backfill してから NOT NULL 制約を付与するマイグレーションを追加

---

## 2026-02-01 06:24 UTC

### system/external actor 方針の明文化

- 要件定義に system user と外部サービス操作の扱いを追記
- 外部サービス操作は MVP では system user に集約し、識別子は event payload に記録する方針

---

## 2026-02-01 06:26 UTC

### system user 表示名と外部操作の表記ルール

- system user は UI 上「System」固定表示とするルールを追記
- 外部サービス由来の操作は「System（source: <service>）」で表記するルールを追記
- event payload に `source`/`external_actor_id`/`external_actor_name`/`external_ref` を記録する仕様を追記
- チケット会話ログの送信者表示で system user を「System」表記に統一

---

## 2026-02-01 06:33 UTC

### 依頼者セレクトの system user 表記

- 新規チケット作成の依頼者セレクトで system user を「System」表記に統一

---

## 2026-02-01 07:26 UTC

### 将来構想: チケット/タスク優先度の齟齬チェック

- チケットとタスクの優先度が内容と乖離していないかをチェックする仕組みを要件に追記

---

## 2026-02-01 07:30 UTC

### 設計メモ追加（優先度齟齬チェック）

- LLMを中心にした齟齬チェックの設計メモを追加
- 要件定義から設計メモへのリンクを追記

---

## 2026-02-01 07:35 UTC

### 設計メモ更新（RAG vs API 比較）

- RAG/ベンダー内蔵検索/素のLLM APIの比較と、コスト・速度・精度・実装難易度の観点を追記
- OpenAI/Gemini の公式ドキュメントと価格表への参照を追記

---

## 2026-02-01 07:52 UTC

### 設計メモ更新（トリアージ通知・緊急度/優先度の分離）

- Urgency（申告）と Priority（トリアージ結果）を分離する方針を追記
- 「全部P1」対策と通知条件/抑制ルールの案を追記

---

## 2026-02-08 06:50 UTC

### Oban / Cachex / Telemetry の導入

- **Oban** を追加（通知・外部連携の非同期基盤）
  - `config/config.exs` に Oban 設定を追加
  - `mix ecto.gen.migration add_oban` でマイグレーション作成し、`Oban.Migrations.up/0` を実行する形に修正
  - `config/test.exs` は `testing: :manual`
- **Cachex** を追加し `HelpdeskCommander.Cache` を新設（インメモリキャッシュ）
- **Telemetry** に Oban ジョブの主要メトリクスを追加
- Tech Stack の記載を更新（README）

---

## 2026-02-08 07:00 UTC

### Hammer / PlugAttack の導入

- **Hammer**（ETS）を追加して rate limiter の土台を用意
- **PlugAttack** を追加し、IPベースのスロットルとログインの fail2ban を実装
- `HelpdeskCommanderWeb.Endpoint` に Plug を追加
- `conn.remote_ip` ベースなので、将来プロキシ配下で運用する場合は `Plug.RemoteIp` の導入を検討してください。
- `REMOTE_IP_ENABLED=true` を設定すると `RemoteIp` を有効化（`x-forwarded-for` / `x-real-ip` を参照）

---

## 2026-02-08 08:30 UTC

### Inquiry → Ticket 自動生成（Phase 1）

- `Helpdesk.Inquiry` を追加（subject/body/source/requester/ticket の関係）
- `CreateTicket` 変更で Inquiry 作成時に Ticket を自動生成
- `Helpdesk` ドメインに Inquiry を登録
- `add_inquiries` マイグレーション/スナップショットを生成
