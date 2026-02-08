# Tasks

作業状況に合わせて随時更新する。

## 現在
- Ticket 状態遷移の整合性（楽観ロック/専用アクション化）の設計・実装

## 次
- 認証・権限（Leader/Admin の制約、検証・承認フロー）
- 通知の仕組み（フェーズ4想定：Obanジョブ設計）
- タスク優先度履歴 UI と `set_priority` アクションの利用導線

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
