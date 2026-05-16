# Tasks

作業状況に合わせて随時更新する。

## 現在
- [P0] Policy Authorizer 導入（`Ticket` を起点に `policies` へ権限制御を集約）

## 次
- [P0] 共通 Change 抽出 + validations 強化（`ticket_verification` の resolved 制約・日時補完の再利用化）
- [P0] TicketNotification の read アクションへ Preparation 導入（recipient絞り込み・`inserted_at desc` 統一）
- [P0] PII保護の段階導入（`users.email` / `companies.name` を `*_enc + *_hash` へ移行し検索・一意制約を維持）
- [P1] 本文系の暗号化導入（`tickets.description` / `inquiries.body` / `conversation_messages.body` / `users.display_name`）
- [P1] `code_interface` 導入（Domain経由APIへ整理し LiveView/Controller を簡素化）
- [P1] `aggregates` / `calculations` 導入（未読通知数・検証数・最新イベント時刻）
- [P2] `multitenancy` 段階導入（company境界の強制）
- 検索/フィルタ/ソート仕様の確定と実装
- Incident 昇格/降格・タイムライン（フェーズ3）
- 外部通知チャネル（メール/チャット）と重複抑制（通知フェーズ拡張）

## 保留
- Incident 昇格/降格・タイムライン（フェーズ3）
- 監視/チャット/SSO 連携（フェーズ6）
- SLA 監視・レポート（フェーズ5）

## 完了
- コアリソース（Users/Tickets/Tasks）と public_id 方針の実装
- Oban/Cachex/Telemetry の導入
- Hammer/PlugAttack/RemoteIp による基本的な攻撃耐性の導入
- 問い合わせ受付（Inquiry）→ Ticket 自動生成の実装（リソース/変更/マイグレーション生成）
- Ticket 詳細のイベントログ・会話ログの永続化（append-only）とページング基盤
- Ticket 状態遷移の整合性（楽観ロック/専用アクション化）
- 認証・権限（Leader/Admin 制約: verified/closed、priority/assignee確定）
- 検証・承認フロー（`ticket_verifications`、検証入力、承認導線）
- 通知の仕組み（MVP: Oban + `ticket_notifications` 保存）
- タスク優先度履歴 UI と `set_priority` アクションの利用導線
