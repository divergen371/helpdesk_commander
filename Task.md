# Task

## すでにやったこと（完了）

### 1) PostgreSQL 18 移行・運用強化
- Postgres 18 へアップグレード（Docker/CI/Docs 反映）
- pg_upgrade 実施、旧ボリューム削除
- `pg_hba.conf` を `scram-sha-256` に強化
- `password_encryption` を `scram-sha-256` に設定しパスワード再ハッシュ
- `mix precommit` 実行確認

### 2) チケット管理の縦スライス実装
- ルーティング追加: `/tickets`, `/tickets/new`, `/tickets/:public_id`
- LiveView:
  - 一覧（stream で表示）
  - 新規作成（`AshPhoenix.Form`）
  - 詳細・更新（`AshPhoenix.Form`）
- `priv/repo/seeds.exs` でデフォルトユーザー作成
- LiveView テスト追加

### 3) チケットコメント機能（会話ログ）
- `ticket_messages` リソース追加（Ash）
- マイグレーション/スナップショット生成
- Ticket 詳細画面に会話ログ表示＋コメント追加フォームを実装
- `latest_message_at` を更新
- テスト拡張

### 4) プロパティベーステスト準備
- `stream_data` 依存追加
- `HelpdeskCommander.PropertyCase` 追加

### 5) PropEr 導入＆実行
- `proper` 依存追加
- PropEr の property を追加（`test/support/proper_public_id.erl`）
- ExUnit から `:proper.quickcheck/2` を実行するテスト追加
- `erlc_paths` 追加で `.erl` をテスト時にコンパイル
- `mix precommit` で検証

### 6) ドキュメント更新
- `docs/Walkthrough.md` に作業ログを日時付きで追記

---

## これからやること（未完了）

### A. 要件定義（docs/REQUIREMENTS.md）突き合わせで見えた不足（フェーズ1/MVP）
優先度高い順（MVPを閉じるために必要）
- Inquiry（Webフォーム）→ Ticket 自動生成（現状は `/tickets/new` の手動作成のみ）
- チケットチャット2系統（公開/非公開）
  - 非公開は requester から閲覧不可にする（権限/可視性）
- イベントログ（ticket_events）
  - 状態変更/担当変更/優先度変更/コメント投稿などを監査可能にする
- チケット一覧のフィルタ/ソート（状態/担当/優先度/種別）
- チャット/履歴のページング（大量データを前提にスケール）

### B. 機能拡張
- タスク管理（5.6）: DB/Resource（Tasks.Task）はあるが、CRUD UI（/tasks のLiveView等）が未実装
  - 予定: 一覧→新規作成→詳細/更新（担当者/期限/優先度/ステータス）
- チケットへのタスク紐付け
- チケット詳細へのイベント履歴（ticket_events）表示
- コメントの削除/編集/メタ情報（メッセージ種別など）

### C. 認証・権限（フェーズ2以降だが、MVP要件にも前提として影響）
- 認証導入（AshAuthentication など）
  - 要件: 未ログイン受付は許容しない（Inquiry作成にログイン必須）
- 役割ごとのアクセス制御（admin/leader/agent/user）
  - 優先度変更、verified/closed 遷移、incident 宣言などを制限
  - system user の role（`system`）と表示名ルールの整理

### D. 検証・承認フロー（フェーズ2）
- resolved → 検証入力（依頼者含む）
- leader/admin による承認（verified/closed）と監査情報（誰がいつ）

### E. 障害管理（Incident）（フェーズ3）
- ticket → incident 昇格/降格、SEV、タイムライン

### F. 優先度・SLA（フェーズ2〜5）
- Impact×Urgency から優先度算出（設計）
- SLA定義/監視/可視化

### G. 品質・運用
- PropEr のテスト拡充（Ticket/Task の性質）
- CI で PropEr テストも実行
- データ移行／バックアップ手順の整理

### H. UI/UX
- チケット詳細の情報構造の整理（可読性・操作性向上）
- 一覧の検索/フィルタ/ソート
- ページング/無限スクロール

---

## 補足
- 詳細な時系列は `docs/Walkthrough.md` を参照。
