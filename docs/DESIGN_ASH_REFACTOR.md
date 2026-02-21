# Ash設計改善メモ（Policy / Changes / Preparation / Interface）

## 目的
- 権限・検証・集計ロジックを Ash の標準機能に寄せ、散在した実装を一元化する。
- LiveView/Controller 側の責務を薄くし、仕様漏れと回 regressions を減らす。

## 優先度順ロードマップ

### P0（最優先）
1. Policy Authorizer 導入
   - 対象: `lib/helpdesk_commander/helpdesk/ticket.ex` を中心に、権限判定を `policies` へ寄せる。
   - 目的:
     - `change` 内の権限判定と UI 側表示制御の差分漏れを防止
     - `verified/closed`・`priority/assignee` 更新の権限制御を一元化

2. 共通 Change 抽出 + validations 強化
   - 対象:
     - `lib/helpdesk_commander/helpdesk/ticket_verification.ex`
     - 新規候補:
       - `lib/helpdesk_commander/helpdesk/changes/ensure_ticket_resolved.ex`
       - `lib/helpdesk_commander/support/changes/set_utc_now_if_nil.ex`
   - 目的:
     - `resolved` 制約や `verified_at` 付与などの再利用化
     - ルールの宣言化、テスト容易性向上

3. Preparation の導入（通知 read アクション）
   - 対象: `lib/helpdesk_commander/helpdesk/ticket_notification.ex`
   - 追加方針:
     - `:for_recipient`
     - `:unread_for_recipient`
     - `prepare` で recipient 絞り込み + `inserted_at desc` 共通化
   - 目的:
     - 取得ロジック重複排除
     - UI 側クエリ組み立ての簡素化

### P1（重要）
4. `code_interface` 導入
   - 対象: `Helpdesk` domain と主要 resource
   - 目的:
     - `Ash.Changeset.for_*` 呼び出しの乱立を整理
     - API境界の明確化（LiveView/Controller は domain 関数を呼ぶ）

5. `aggregates` / `calculations` 導入
   - 候補:
     - 未読通知件数
     - チケット検証数
     - 最新イベント時刻
   - 目的:
     - 集計ロジックを resource 側へ移し、画面ロジックを薄くする

### P2（中期）
6. `multitenancy`（company境界）導入
   - 目的:
     - `company_id` 境界をフレームワーク側で強制
     - データ分離の安全性を恒常的に担保
   - 注意:
     - 段階導入（read→write）と既存クエリ互換の確認が必要

## 実装順の提案（最小リスク）
1. 共通 Change 抽出（副作用が少ない）
2. TicketNotification Preparation 追加
3. Policy Authorizer 導入（Ticket → TicketVerification の順）
4. code_interface 導入
5. aggregates/calculations 導入
6. multitenancy PoC → 本導入

## 完了条件
- 権限・検証ロジックが resource 側 DSL に集約される
- 通知 read の絞り込み/並び替えが Preparation 経由で統一される
- LiveView/Controller の Ash 呼び出しが `code_interface` 経由へ移行される
- PBT + 既存テスト（`mix precommit`）がグリーン
