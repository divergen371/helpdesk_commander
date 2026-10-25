# ロードマップ

最終更新: 2026-10-24
基準: [REQUIREMENTS.md](REQUIREMENTS.md) の段階導入（フェーズ 1〜6）と、[STATUS.md](STATUS.md) の実装調査。

凡例: ✅ 完了 / 🟡 一部実装 / ⬜ 未着手

---

## サマリ

| フェーズ | テーマ | 状態 | 次に閉じる条件 |
| --- | --- | --- | --- |
| 0 | 基盤・開発環境 | ✅ | — |
| 1 | 受付〜チケット運用（MVP） | 🟡 | タスク CRUD |
| 2 | 認証・権限・検証/承認 | 🟡 | リソース横断ポリシー、PII 暗号化、カバレッジの余裕確保 |
| 3 | 障害管理（Incident） | ⬜ | Incident リソース・昇格/降格・タイムライン |
| 4 | コラボレーション強化 | 🟡 | 添付、通知 UI、コメント編集/削除、関連リンク UI |
| 5 | SLA・分析・レポート | ⬜ | SLA 定義/監視、ダッシュボード、統計 |
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
- ⬜ **タスク CRUD UI**
  - 一覧/詳細に加えて作成・編集・削除、担当/期限/状態の変更
- ⬜ **タスクとチケットの紐付け**
- ⬜ **製品マスタ管理 UI**（作成・編集・無効化）
- ⬜ **チケット関連リンク UI**（関連/重複/ブロック）

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

- ⬜ **テナント境界の監査と統一**
  - 全社横断の閲覧・操作が要件通りか確定する
  - 担当者候補、通知受信者、管理操作を `company_id` で制約する
- ⬜ **Ash ポリシーの横展開**
  - Task / Inquiry / ConversationMessage / TicketNotification / TicketLink
  - LiveView の手動チェックからリソース側へ寄せる
- ⬜ **共通 Change / Validation の抽出**
  - 検証の `resolved` 制約、日時補完、会社ID補完の再利用化
- ⬜ **TicketNotification read の Preparation**
  - 受信者で絞り、`inserted_at desc` を統一
- ⬜ **PII 暗号化（段階導入）**
  - `users.email` / `companies.name` を `*_enc + *_hash` へ
  - 検索・一意制約を維持
- ⬜ **本文系の暗号化**
  - `tickets.description` / `inquiries.body` / `conversation_messages.body` / `users.display_name`
- ⬜ **Impact × Urgency → 優先度算出**
  - 現状は `impact` / `urgency` の保持のみ
- ⬜ **`code_interface` / `aggregates` / `calculations`**
- ⬜ **`multitenancy`（company 境界の強制）**
- ⬜ **カバレッジの余裕確保**（現在 80.9%）

---

## フェーズ 3: 障害管理（Incident）

- ⬜ Ticket → Incident 昇格/降格（admin/leader のみ）
- ⬜ SEV（重大度）と影響範囲
- ⬜ タイムライン（調査 / 暫定対応 / 復旧 / 監視 / 振り返り）
- ⬜ 周知用メモ
- ⬜ P1 かつ SEV=P1 の全体公開候補と手動承認

---

## フェーズ 4: コラボレーション強化

- 🟡 コメント（公開/内部メモ）— 追加のみ。編集・削除は未実装
- ✅ 通知 UI と既読管理
- ⬜ 通知の重複抑制・クールダウン
- ⬜ 外部通知（メール / チャット）
- ⬜ 添付ファイル（容量・形式・保存先・ウイルススキャン）
- ⬜ チケット関連リンクの自動提案・重複検知

---

## フェーズ 5: SLA・分析・レポート

- ⬜ SLA 定義（優先度ごとの一次応答 / 暫定対応 / 解決 / 復旧）
- ⬜ SLA 監視と可視化
- ⬜ ダッシュボード（未対応、滞留、負荷）
- ⬜ レポート・統計
- ⬜ 優先度と内容の齟齬チェック（`DESIGN_PRIORITY_CHECK.md`）

---

## フェーズ 6: 外部連携

- ⬜ 監視サービス連携
- ⬜ チャット連携（Slack など）
- ⬜ SSO
- ⬜ JSON API / GraphQL（`DESIGN_API_MIGRATION.md`）

---

## 優先バックログ

### P0（最優先）

| # | タスク | 受け入れ条件 |
| --- | --- | --- |
| 1 | ~~CI カバレッジ回復~~ | ✅ 完了（80.9%） |
| 2 | ~~実行環境の固定~~ | ✅ 完了（OTP 29.1.2 / Elixir 1.20.4） |
| 3 | ~~Inquiry Web フォーム~~ | ✅ 完了（`/inquiries/new` → Ticket 自動生成） |
| 4 | ~~テナント/権限の監査~~ | ✅ 完了（company 境界・社外タスク禁止・特権操作の会社一致） |
| 5 | 共通 Change 抽出 | `ticket_verification` の resolved 制約・日時補完が共通 Change に移り、既存テストが通る |
| 6 | ~~通知 read の Preparation~~ | ✅ 完了（受信者絞り込み・新しい順・read/mark_read ポリシー） |

### P1（MVP 仕上げ）

| # | タスク | 受け入れ条件 |
| --- | --- | --- |
| 7 | ~~チケット一覧のフィルタ/ソート/ページング~~ | ✅ 完了（URL クエリで再現可能） |
| 8 | ~~通知 UI~~ | ✅ 完了（未読件数・一覧・既読化・受信者スコープ） |
| 9 | タスク CRUD UI | 作成・編集・削除・担当/期限/状態変更の LiveView テスト |
| 10 | チケットとタスクの紐付け | チケット詳細から関連タスクを確認・追加できる |
| 11 | チケット関連リンク UI | 関連/重複/ブロックを登録・表示できる |
| 12 | PII 暗号化（第1段） | email / company name が暗号化され、検索と一意制約が維持される |
| 13 | `code_interface` / aggregates | LiveView から Domain API 経由に整理。未読数・検証数を集計 |
| 14 | カバレッジの継続運用 | 新規コード追加時に 80% を下回らない |
| 15 | Ash snapshot 再生成 | `mix ash.codegen --check` が成功。`ticket_messages` DROP は手動承認のうえ適用 |

### P2（拡張）

| # | タスク |
| --- | --- |
| 16 | `multitenancy` による company 境界の強制 |
| 17 | Incident 昇格/降格・SEV・タイムライン |
| 18 | SLA 定義・監視・ダッシュボード |
| 19 | 添付ファイル |
| 20 | 外部通知 / 監視 / チャット / SSO |
| 21 | JSON API 化 |

---

## マイルストーン

1. **M1: MVP クローズ** — P0 の 5 + P1 の 9〜11
2. **M2: セキュリティ/品質強化** — P0 の 4〜6、P1 の 12〜14、P2 の 15
3. **M3: Incident 運用** — フェーズ 3
4. **M4: 分析・外部連携** — フェーズ 5〜6

各マイルストーンの完了時は [STATUS.md](STATUS.md) と [TASKS.md](TASKS.md) を更新する。
