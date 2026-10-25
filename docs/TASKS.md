# Tasks

作業状況に合わせて随時更新する。
全体像とフェーズは [ROADMAP.md](ROADMAP.md)、現状の検証結果は [STATUS.md](STATUS.md) を参照。

最終更新: 2026-10-25

## 現在（P0）

- [ ] 共通 Change 抽出 + validations 強化（`ticket_verification` の resolved 制約・日時補完の再利用化）
- [ ] PII保護の段階導入（`users.email` / `companies.name` を `*_enc + *_hash` へ移行し検索・一意制約を維持）

## 次（P1）

- [ ] チケット関連リンク UI（`ticket_links` の登録・表示）
  - [ ] Sigma.js による関係グラフ PoC（ノード/エッジ/座標/スコア、ホバー強調）
- [ ] 製品マスタ管理 UI
- [ ] コメントの編集/削除/メタ情報（メッセージ種別など）
- [ ] 本文系の暗号化導入（`tickets.description` / `inquiries.body` / `conversation_messages.body` / `users.display_name`）
- [ ] `code_interface` 導入（Domain経由APIへ整理し LiveView/Controller を簡素化）
- [ ] `aggregates` / `calculations` 導入（未読通知数・検証数・最新イベント時刻）
- [ ] Ash ポリシーの横展開（Task / Inquiry / ConversationMessage / TicketNotification / TicketLink）
- [ ] 検索/フィルタ/ソート仕様の確定と実装
- [ ] 通知の重複抑制・クールダウン
- [ ] 外部通知チャネル（メール/チャット）と重複抑制（通知フェーズ拡張）
- [ ] カバレッジの余裕確保（現在 81.3%。worker / `ticket_live/show.ex` の未テスト分を追加）
- [ ] Ash resource snapshot の再生成（`mix ash.codegen --check` の 8 ファイル。`ticket_messages` DROP を含むため手動レビュー）

## 保留（P2）

- [ ] `multitenancy` 段階導入（company境界の強制）
- [ ] Incident 昇格/降格・タイムライン（フェーズ3）
- [ ] Incident の SEV・影響範囲・周知メモ
- [ ] SLA 定義・監視・レポート（フェーズ5）
- [ ] ダッシュボード・統計
- [ ] 添付ファイル（保存先・容量・形式・ウイルススキャン）
- [ ] 監視/チャット/SSO 連携（フェーズ6）
- [ ] JSON API 化（`DESIGN_API_MIGRATION.md`）
- [ ] AshAuthentication への一本化（現行 `Accounts.Auth` との差異整理）

## 完了

- [x] チケットとタスクの紐付け（`ticket_task_links`、チケット詳細から追加・解除、company 検証）
- [x] タスク CRUD UI（作成・編集・削除、担当/期限/状態変更、入力検証、担当者の company 検証）
- [x] 通知 UI（`/notifications`、受信者別一覧、未読件数、既読化、チケット導線）
- [x] チケット一覧のフィルタ/ソート/ページング（状態/優先度/種別/担当、URL クエリ、20件ページング）
- [x] Inquiry Web フォーム（`/inquiries/new`、製品選択、依頼者指定、Ticket 自動生成、テナント検証）
- [x] テナント境界・認可監査（チケット/タスク/ユーザー承認を `company_id` で制約、社外のタスクアクセス禁止、横断的な特権操作を拒否）
- [x] TicketNotification read の Preparation（受信者絞り込み・`inserted_at desc`・read/mark_read ポリシー）
- [x] Erlang/OTP 29.1.2 + Elixir 1.20.4 対応（`.tool-versions` / CI 更新、Ash/Phoenix 依存更新、型警告修正）
- [x] CI カバレッジ 80% 回復（CurrentUser / Authorization / 認証コントローラのテスト追加）
- [x] コアリソース（Users/Tickets/Tasks）と public_id 方針の実装
- [x] Oban/Cachex/Telemetry の導入
- [x] Hammer/PlugAttack/RemoteIp による基本的な攻撃耐性の導入
- [x] 会社・ユーザー認証（会社コード + login_id/email、pending 承認）
- [x] ユーザーの停止・匿名化（suspended → 30日後 anonymized）
- [x] 問い合わせ受付（Inquiry）→ Ticket 自動生成の実装（リソース/変更/マイグレーション生成）
- [x] Ticket 詳細のイベントログ・会話ログの永続化（append-only）とページング基盤
- [x] Ticket 状態遷移の整合性（楽観ロック/専用アクション化）
- [x] 認証・権限（Leader/Admin 制約: verified/closed、priority/assignee確定）
- [x] 検証・承認フロー（`ticket_verifications`、検証入力、承認導線）
- [x] 通知の仕組み（MVP: Oban + `ticket_notifications` 保存）
- [x] タスク優先度履歴 UI と `set_priority` アクションの利用導線
- [x] Policy Authorizer 導入（`Ticket.set_status` / `Ticket.update` の権限制御を `policies` に集約）
- [x] 製品マスタ（`products`）とチケット作成時の選択
- [x] チケット関連リンクのリソース（`ticket_links`）
- [x] PropCheck による PBT（StateM / FSM / negative）と CI 設定

## 補足

- 詳細な時系列は `docs/Walkthrough.md` を参照。
- 設計メモ:
  - `docs/DESIGN_ASH_REFACTOR.md`
  - `docs/DESIGN_DATA_ENCRYPTION.md`
  - `docs/DESIGN_API_MIGRATION.md`
  - `docs/DESIGN_PRIORITY_CHECK.md`
  - `docs/DESIGN_TICKET_RELATIONS.md`
  - `docs/DESIGN_USER_DELETION.md`
