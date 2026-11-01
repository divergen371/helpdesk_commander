# ロードマップ

最終更新: 2026-11-01
基準: [REQUIREMENTS.md](REQUIREMENTS.md) の段階導入（フェーズ 1〜6）と、[STATUS.md](STATUS.md) の実装調査。

凡例: ✅ 完了 / 🟡 一部実装 / ⬜ 未着手

未完了タスクの正本は Backlog.md（`backlog/`）とする。このファイルはフェーズ構成と完了状況のみを扱う。

---

## サマリ

| フェーズ | テーマ | 状態 | 次に閉じる条件 |
| --- | --- | --- | --- |
| 0 | 基盤・開発環境 | ✅ | — |
| 1 | 受付〜チケット運用（MVP） | ✅ | — |
| 2 | 認証・権限・検証/承認 | ✅ | ポリシー横展開とカバレッジの余裕確保まで完了 |
| 3 | 障害管理（Incident） | 🟡 | 昇格/降格・SEV・影響範囲・周知メモ・タイムラインは実装済み。全体公開承認は未着手 |
| 4 | コラボレーション強化 | 🟡 | 添付、通知 UI、関連リンク UI（コメント編集/削除は完了） |
| 5 | SLA・分析・レポート | 🟡 | SLA 定義/監視と簡易ダッシュボードは実装済み。統計・レポートは未着手 |
| 6 | 外部連携 | ⬜ | 監視/チャット通知、SSO |

---

## フェーズ 1: 受付〜チケット運用（MVP）

### 完了

- ✅ Phoenix / Ash / PostgreSQL 18 / Docker / CI の基盤
- ✅ Users / Companies / Products / Tickets / Tasks のリソース
- ✅ `public_id` 方針
- ✅ Inquiry リソース・Web フォームと Ticket 自動生成
- ✅ チケット一覧・新規作成・詳細
- ✅ 公開チャット / 内部メモ / イベントログ（append-only）
- ✅ 状態遷移、楽観ロック、監査イベント
- ✅ チャット・イベントのページング
- ✅ 検証結果の登録と承認（admin/leader）
- ✅ 通知レコードの生成（Oban、アプリ内保存）と通知 UI（一覧・未読・既読化）

### 残り

- ✅ **Inquiry Web フォーム**（`/inquiries/new`）
  - ログイン必須、製品マスタ選択、subject/body のサーバ側検証、送信後に Ticket へ遷移
- ✅ チケット一覧のフィルタ/ソート/ページング
- ✅ 通知 UI（一覧・未読件数・既読化・受信者スコープ）
- ✅ タスク CRUD UI（作成・編集・削除、担当/期限/状態変更、優先度履歴）
- ✅ チケットとタスクの紐付け（チケット詳細から追加・解除）
- ✅ **製品マスタ管理 UI**（作成・編集・無効化）
- ✅ **チケット関連リンク UI**（関連/重複/ブロック）
- ✅ **Sigma.js 関係グラフ PoC**

### 完了条件（MVP クローズ）

1. 社外ユーザーがログインし、Inquiry フォームから問い合わせを送信できる。
2. 自動生成された Ticket が一覧・詳細に表示され、公開チャットでやり取りできる。
3. 社内ユーザーが状態・優先度・担当を更新でき、操作がイベントログに残る。
4. resolved → 検証入力 → admin/leader 承認（verified/closed）が画面から完了できる。
5. 一覧が条件指定とページングで実用件数に耐える。
6. 通知が受信者にだけ表示され、既読にできる。
7. `mix precommit` と CI が成功する。

---

## フェーズ 2: 認証・権限・検証/承認

### 完了

- ✅ 会社コード + login_id/email + パスワード認証
- ✅ 仮ユーザー（pending）→ 管理者承認
- ✅ suspended / anonymized と遅延匿名化
- ✅ admin / leader による優先度・担当の確定、verified/closed 遷移
- ✅ Ticket の Policy Authorizer 導入
- ✅ 検証・承認フローと監査イベント

### 残り

- ✅ **テナント境界の監査と統一**
  - 担当者候補、通知受信者、管理操作を `company_id` で制約済み
- ✅ **Ash ポリシーの横展開**
  - Task / Inquiry / ConversationMessage / TicketLink（TicketNotification は既存）
  - 更新・削除・メッセージ編集をリソース側で制御し、画面から actor を渡す
- ✅ **共通 Change / Validation の抽出**
  - `EnsureTicketResolved` / `SetTimestampIfNil` を追加し、検証の `resolved` 制約と日時補完を再利用化
- ✅ **TicketNotification read の受信者制御**
  - read ポリシーで受信者に限定。Preparation は廃止し、並び順は build sort で維持
- ✅ **PII 暗号化（段階導入）**
  - `users.email` / `companies.name` を `encrypted_* + *_hash` へ（AshCloak + Cloak）
  - 検索・一意制約は hash で維持
- ✅ **本文系の暗号化**
  - `tickets.description` / `inquiries.body` / `conversation_messages.body` / `users.display_name`
- ✅ **Impact × Urgency → 優先度算出**（HC-14）
  - 4x4 の算出表、`priority_source`（auto/manual）、明示指定の優先と次回再算出
- ✅ **`code_interface` / `aggregates` / `calculations`**
  - `code_interface` と Domain API（`Accounts` / `Helpdesk` / `Tasks`）を導入
  - aggregates: 未読通知数・チケット検証数・最新イベント時刻
- ✅ **`multitenancy`（company 境界の強制）**（HC-2: attribute tenant + actor scope + write guard）
- ✅ **カバレッジの余裕確保**（82.5%）

---

## フェーズ 3: 障害管理（Incident）

- ✅ Ticket → Incident 昇格/降格（admin/leader のみ）（HC-3）
- ✅ SEV（重大度）・影響範囲・周知メモ
- ✅ タイムライン（調査 / 暫定対応 / 復旧 / 監視 / 振り返り）
- ⬜ 周知用メモ
- ⬜ P1 かつ SEV=P1 の全体公開候補と手動承認

---

## フェーズ 4: コラボレーション強化

- ✅ コメント（公開/内部メモ）— 追加・編集・論理削除、種別と編集日時の表示
- ✅ 検索・フィルタ・ソート（仕様は `docs/DESIGN_SEARCH_FILTER_SORT.md`）
- 🟡 関係グラフ — `/relations` で俯瞰表示（HC-1）
- ✅ 通知 UI と既読管理
- ✅ 通知の重複抑制・クールダウン（同一チケット・種別・受信者の 5 分以内は抑止）
- ✅ 外部通知（メール / チャット Webhook）— クールダウンと送信済み記録で重複を防止
- ⬜ 添付ファイル（容量・形式・保存先・ウイルススキャン）（HC-6）
- ⬜ チケット関連リンクの自動提案・重複検知（HC-15）

---

## フェーズ 5: SLA・分析・レポート

- ✅ SLA 定義（優先度ごとの一次応答 / 暫定対応 / 解決 / 復旧）（HC-4）
- ✅ SLA 監視と可視化（達成/逸脱判定、ダッシュボードの逸脱件数）（HC-4）
- ✅ 簡易ダッシュボード（チケット・タスク・製品・通知の概要）
- ⬜ ダッシュボードの分析機能（未対応、滞留、負荷）（HC-5）
- ⬜ レポート・統計
- ⬜ 優先度と内容の齟齬チェック（`DESIGN_PRIORITY_CHECK.md`）

---

## フェーズ 6: 外部連携

- ⬜ 監視サービス連携（HC-8）
- ⬜ 会話チャット連携（Slack など。通知 Webhook は実装済み）（HC-7）
- ⬜ SSO（HC-9）
- ⬜ JSON API / GraphQL（`DESIGN_API_MIGRATION.md`）（HC-11）

---

## フェーズ 7: AI・意思決定支援

- ⬜ **LiquidAI のデシジョンモデル（D1 / D1 Ultra）の導入検討**（HC-13）
  - 想定用途: チケットの優先度・担当・エスカレーション判定、SLA 逸脱リスク、重複/関連チケットの候補提示
  - D1 と D1 Ultra の精度・レイテンシ・コスト・セルフホスト可否を比較し、選定基準を先に確定する
  - 推論結果は判断材料として提示し、最終決定は人間が行う（自動確定は段階的に許可）
  - PII を外部送信しない構成（セルフホストまたは匿名化）を前提とする
  - 評価データセットとオフライン評価を用意し、シャドー運用で精度を確認してから有効化する
- ⬜ 決定ログと説明可能性（入力・モデル版・出力・採用/却下理由）
- ⬜ モデル障害時のフォールバック（既存のルールベース判定を維持）

---

## マイルストーン

実行単位は Backlog.md のマイルストーンで管理する。

| ID | 名称 | 主なタスク |
| --- | --- | --- |
| M1 | MVP クローズ | HC-1 |
| M2 | 品質・セキュリティ | HC-2, HC-10, HC-12, HC-14 |
| M3 | Incident 運用 | HC-3 |
| M4 | 分析・外部連携 | HC-4, HC-5, HC-6, HC-7, HC-8, HC-9, HC-11, HC-15 |
| M5 | AI・意思決定支援 | HC-13 |

各マイルストーンの完了時は `STATUS.md` を更新する。
