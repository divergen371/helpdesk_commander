# Implementation Plan

このドキュメントは「実装計画」を記録し、作業進行に合わせて更新する。
実装後に判明したこと（できた/できなかった・懸念点）は末尾に追記する。

## 目的
- MVPで「問い合わせ→チケット→対応→検証→承認」の運用を成立させる
- 監査性・堅牢性・性能を満たす基盤（イベント/会話ログ、通知、レート制限）を整備する

## 現状
- コアリソース（Users/Tickets/Tasks）と `public_id` 方針は実装済み
- Oban / Cachex / Telemetry / Hammer / PlugAttack / RemoteIp を導入済み
- Inquiry は実装済み（自動 Ticket 生成まで）
- Conversation / Event 系のリソースを実装済み（ページング基盤含む）
- Task 優先度履歴 UI と `set_priority` 導線を実装済み
- Ticket の `set_status` / `update` 権限制御は Policy Authorizer に移行済み

## 設計方針
- 重要操作はイベントログ化し、append-only を基本にする
- チャット/イベントはページング前提で設計し、LiveView の状態肥大化を避ける
- 状態遷移は専用アクション化し、楽観ロックで競合を検知する

## 実装方針
- Phase 1: Inquiry → Ticket 自動生成の実装
- Phase 1: チケット詳細の会話ログ/イベントログの永続化とページング基盤
- Phase 2: 認証・権限（Leader/Admin制約）と検証/承認フロー
- Phase 4: 通知（Oban ジョブ）を最小構成で導入

## リスク / 検証
- 競合更新: `lock_version` を使った stale update 検知のテストを用意
- メッセージ量: LiveView streams + ページングで負荷を検証
- 通知/外部連携: Oban の失敗リトライと可視化（Telemetry）で監視

## 関連設計メモ
- Ash機能への寄せ方（Policy/Change/Preparation/code_interface/aggregate/multitenancy）:
  - `docs/DESIGN_ASH_REFACTOR.md`
- データ暗号化（AshCloak + 検索ハッシュ）:
  - `docs/DESIGN_DATA_ENCRYPTION.md`
## 実装後メモ（結果・未達・懸念）
- Inquiry リソースと `CreateTicket` 変更を追加し、Inquiry 作成時に Ticket を自動生成する流れを実装
- `add_inquiries` マイグレーション/スナップショットを生成
- Inquiry の UI/テスト/運用フローは未着手
- UI差し替え（React/Vue/Corex等）に伴う JSON API 化の設計メモを `docs/DESIGN_API_MIGRATION.md` に追加
  - 段階移行の方針、認証（Cookie/Token）、エラー標準、セキュリティ、テスト方針、AshJsonApi/GraphQL 拡張の選択肢を整理
- Task 一覧/詳細 UI を追加し、詳細画面から `set_priority` 経由で優先度変更と履歴表示を行えるようにした
  - company 境界は LiveView の read 側フィルタで担保。将来は multitenancy / Policy Authorizer に寄せる
  - `Task.update` では引き続き priority 変更が可能なため、履歴必須の導線は UI で `set_priority` を使う前提。後続で update から priority を外すか専用アクションへさらに寄せる検討余地あり
- Ticket に Ash Policy Authorizer を導入し、`set_status` の `verified/closed` 遷移と `update` の `priority/assignee_id` 更新を policy check で制御するようにした
  - 既存の `actor_id` 引数はイベント記録互換として維持し、LiveView からは `action_opts: [actor: current_user]` も渡す
  - UI 側の表示抑制は維持しつつ、サーバ側の Forbidden は専用 flash に変換
  - Ash の policy verifier 向けに `picosat_elixir` を追加
