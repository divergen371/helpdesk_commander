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

## 2026-02-09

### 認証/テナント周りの調整とprecommit完走

- `visibility_scope` の制約を文字列の `match` に修正
- `AshAuthentication` のパスワード戦略依存を外し、`HashPassword` 変更でハッシュ化
- `LiveUserAuth` のガード/assign整備、循環依存を解消
- `AssignCompanyFromRequester` / `AssignCompanyFromTicket` を共通化
- サンプルユーザー表示条件の調整、管理者承認ボタンの属性修正
- `mix precommit` を通過（100 tests / 0 failures）

---

## 2026-02-08 08:47 UTC

### mix precommit --all のエラー修正

- `Mix.Tasks.Precommit` を追加して `--all` を Credo にだけ渡すように調整
- `mix precommit` は従来通りの実行内容を維持

---

## 2026-02-08 08:54 UTC

### Dialyzer 警告の対策（CreateTicket change/3）

- `Ash.create/2` の 3 タプル戻り値（通知付き）を明示的に処理
- `before_action` 内の `case` を網羅し、Dialyzer の警告回避

---

## 2026-02-08 09:22 UTC

### ベンチ/デバッグ/カバレッジの導入（CI連携）

- Benchee/observer_cli/ExCoveralls を追加
- CI のテストジョブを `mix coveralls.github` に変更
- `test_coverage` と `preferred_cli_env` を設定

---

## 2026-02-08 09:38 UTC

### カバレッジ閾値とHTMLレポート保存

- `coveralls.json` で閾値（minimum_coverage）を設定
- CI で `mix coveralls.html` を生成し成果物として保存

---

## 2026-02-08 09:58 UTC

### カバレッジ向上のためのテスト追加

- Inquiry 作成時に Ticket が生成されることを検証
- Cache / Repo / BigInt / DataCase / PropertyCase の補助テストを追加
- カバレッジ 80.1% を確認

---

## 2026-02-08 07:00 UTC

### Hammer / PlugAttack の導入

- **Hammer**（ETS）を追加して rate limiter の土台を用意
- **PlugAttack** を追加し、IPベースのスロットルとログインの fail2ban を実装
- `HelpdeskCommanderWeb.Endpoint` に Plug を追加
- `conn.remote_ip` ベースなので、将来プロキシ配下で運用する場合は `Plug.RemoteIp` の導入を検討してください。
- `REMOTE_IP_ENABLED=true` を設定すると `RemoteIp` を有効化（`x-forwarded-for` / `x-real-ip` を参照）

---

## 2026-02-08 12:45 UTC

### Ticket 会話/イベントログの基盤化（append-only + ページング）

- `Conversation` / `ConversationMessage` / `TicketEvent` を追加
- `ticket_messages` → `conversation_messages` への移行を含むマイグレーションを追加
- Ticket 作成時に公開/非公開 Conversation と `ticket_created` イベントを作成
- メッセージ投稿で `latest_message_at` 更新 + `message_posted` イベント記録
- Ticket 詳細 UI を公開/内部/イベントログの3セクションに分割しページング対応
- LiveView テストを更新

---

## 2026-02-08 08:30 UTC

### Inquiry → Ticket 自動生成（Phase 1）

- `Helpdesk.Inquiry` を追加（subject/body/source/requester/ticket の関係）
- `CreateTicket` 変更で Inquiry 作成時に Ticket を自動生成
- `Helpdesk` ドメインに Inquiry を登録
- `add_inquiries` マイグレーション/スナップショットを生成

---

## 2026-02-08 08:42 UTC

### Dialyzer 修正（CreateTicket の before_action）

- `Ash.Changeset.before_action/2` のコールバックを arity 1 に修正し、Dialyzer エラーを解消

---

## 2026-02-08 13:56 UTC

### 未決定事項リストの追加

- `docs/UNDECIDED_ITEMS.md` に優先順位付きの未決定事項を整理

---

## 2026-02-08 14:08 UTC

### 利用者・ロール方針の明確化

- 顧客（社外）も利用者に含むこと、チケットは全ユーザー全件閲覧可能と明記
- 検証・承認の確定は管理者/リーダーのみ
- 優先度・担当者アサインの変更入力は誰でも可能だが、確定は管理者/リーダーのみ

---

## 2026-02-08 14:17 UTC

### バリデーション仕様・サニタイズ方針の決定

- MVPはプレーンテキストのみ、Markdown/HTMLは許可しない
- サーバ側で必須/長さ/形式/列挙値を検証し、空白のみ入力は無効
- 表示時は文脈エスケープを必須
- 最大長（Inquiry/Ticket/ConversationMessage）を要件に明記

---

## 2026-02-09 14:02 UTC

### 画面設計・画面遷移の決定

- 画面は一覧/新規作成/詳細の3画面で開始
- 詳細から一覧へ戻れる導線を用意
- 社外ユーザーは新規作成＋自身作成の一覧/詳細に限定

---

## 2026-02-09 14:25 UTC

### 社外ユーザーの閲覧制限を実装

- session の current_user を参照して社外ユーザーの一覧/詳細を自分のチケットに制限
- 社外ユーザーには内部メモ/イベントログ/ステータス更新を非表示に
- public メッセージ投稿は sender を current_user に固定

---

## 2026-02-09 14:49 UTC

### サインアップ/ログイン/会社運用の方針決定

- 会社作成は社内のみ、会社IDは `A-123456` 形式で入力しDBはHMAC-SHA256でハッシュ保存
- 顧客メールで仮ユーザー作成（pending）→ 管理者承認で有効化
- login_id と display_name を分離し、ログインは会社ID + login_id/email + パスワード
- priority=P1 + incident_sev=P1 は全体公開候補として手動承認で公開

---

## 2026-02-09 15:50 UTC

### 認証/会社テナント化の実装

- `companies` を追加し、company_code はHMACでハッシュ保存
- `users` を multi-tenant 仕様に拡張（company_id / login_id / display_name / password_hash / status）
- 会社ID + login_id/email のサインインと初回メールログイン時の login_id 自動生成を実装
- サインアップ/承認（pending→active）画面を追加
- tickets/inquiries/conversations/messages/events を company_id でスコープ化し、global 共有を許可
- テストと seeds を新スキーマに合わせて更新

## 2026-02-08 13:25 UTC

### カバレッジ改善のためのテスト追加

- `Tasks.Task#set_priority` のイベント記録をテストで検証
- `PublicId.generate/1` の異常系（奇数長）をテスト追加
- `PlugAttack` の `block_action` をテストし 429 を確認
- `RemoteIp` の有効/無効切替をテストで検証

---

## 2026-02-11 06:05 UTC

### TicketLive.Show のエラーハンドリング修正とprecommit通過

- `TicketLive.Show` の `load_older_messages` ハンドラを復元し、パースエラーを解消
- メッセージ/イベント取得クエリの組み立てを修正
- `mix precommit` を通過（100 tests / 0 failures）

---

## 2026-02-11 06:12 UTC

### エラーハンドリング指針のドキュメント化

- `docs/ERROR_HANDLING.md` を追加し、失敗の分類・伝播・フォールバック配置の方針を整理

---

## 2026-02-11 06:23 UTC

### チケットの対象製品/サービスの要件追加

- `docs/REQUIREMENTS.md` に対象製品/サービスの指定・表示要件を追記

---

## 2026-02-11 06:40 UTC

### 製品マスタ選択の導入

- `products` テーブルとAshリソースを追加
- `tickets` / `inquiries` に `product_id` を追加して必須化
- チケット作成フォームに製品選択を追加し、詳細/一覧に表示
- 既存データ向けにデフォルト製品を自動作成・割当て

---

## 2026-02-11 07:15 UTC

### カバレッジ改善のためのテスト拡充

- Ticket 詳細で公開/イベントログの「もっと読む」動作をテスト追加
- 内部メモ投稿・社外ユーザーの公開投稿テストを追加
- `CurrentUser` の `:user_id` セッション経路をテスト追加
- `MIX_ENV=test mix coveralls` で **80.5%** を確認

---

## 2026-02-11 08:10 UTC

### Credo のテスト向けチェックを最小化

- `lib/` は従来どおりフルチェックを維持
- `test/` は最小チェック（最低限の整形 + 安全系警告）に限定

---

## 2026-02-11 09:05 UTC

### JSON API 化の設計メモを追加

- `docs/DESIGN_API_MIGRATION.md` を新規作成
- LiveView → React/Vue/Corex 等への UI 差し替えに備えた JSON API 段階移行の方針を整理
- 選択肢（薄い Phoenix コントローラ / AshJsonApi / AshGraphql）、認証、エラー標準、セキュリティ、テスト方針、ロードマップ等を記載

---

## 2026-02-11 16:30 UTC

### チケット状態遷移の整合性（専用アクション化 + 楽観ロック）

- ステータス体系を仕様準拠（`new/triage/in_progress/waiting/resolved/verified/closed`）に統一
- `Ticket.set_status` アクションを追加し、遷移検証・イベント記録・タイムスタンプ付与を集約
- `update` から `status` を外し、`optimistic_lock(:lock_version)` を適用
- LiveView をステータス更新フォームと優先度更新フォームに分離
- 競合更新（StaleRecord）時は最新再読込 + エラーメッセージ表示
