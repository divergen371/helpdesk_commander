# リポジトリ現状レポート

最終更新: 2026-11-01
対象: `main` / `b2f7c30`

このドキュメントは「今どこまで出来ていて、何が動き、何が足りないか」をスナップショットとして残す。
残作業は Backlog.md（`backlog/`）、フェーズの方針は [ROADMAP.md](ROADMAP.md) を参照。

---

## 1. 検証結果（2026-11-01 時点）

### 実行環境

| 項目 | 値 |
| --- | --- |
| Elixir | 1.20.4 |
| Erlang/OTP | 29.1.2 |
| PostgreSQL | 18（Docker Compose） |
| DB | `helpdesk_commander_test` を作成して実行 |

### 実行コマンドと結果

| コマンド | 結果 |
| --- | --- |
| `mix precommit` | 成功 |
| `mix test` | **13 properties, 249 tests, 0 failures** |
| `mix credo --strict` | 指摘なし（65 files / 95 checks） |
| `mix dialyzer` | **0 errors** |
| `mix compile --warnings-as-errors` | 成功（プロジェクト側の警告 0） |
| `mix format` | 差分なし |
| `MIX_ENV=test mix coveralls` | **82.9%**（最低基準 80% を満たす） |

### 環境

- `.tool-versions` で **Erlang 29.1.2 / Elixir `ref:v1.20.4`** を固定
- CI（`.github/workflows/ci.yml`）も同じバージョンに更新
- 依存関係を Elixir 1.20 対応版へ更新
  - Ash 3.37.0 / AshPostgres 2.15.1 / AshPhoenix 2.3.25
  - Phoenix 1.8.16 / Phoenix LiveView 1.2.13 / LiveDashboard 0.9.1
- Elixir 1.20 の型推論警告に対応
  - `CurrentUser.id/1` を追加し、`&&` による nil 分岐を明示化
  - `<.button>` の `type` 属性を許可
  - `show/1,2` / `hide/1,2` の `@spec` を `map()` に変更（LiveView 1.2 の opaque 型対応）
  - Ash 3.37 の必須設定 `default_string_length_count: :codepoints` を追加
- カバレッジ回復のため `CurrentUser` / `Authorization` / 認証コントローラのテストを追加

### カバレッジの内訳（低い順・抜粋）

| モジュール | カバレッジ |
| --- | --- |
| `mix/tasks/precommit.ex` | 0.0% |
| `web.ex` | 30.0% |
| `plug_attack.ex` | 50.0% |
| `ticket/checks/*` | 60.0〜69.2% |
| `workers/create_ticket_notifications_worker.ex` | 81.8% |
| `live/ticket_live/show.ex` | 77.1% |
| `accounts/auth.ex` | 85.6% |
| **合計** | **82.9%**（2279 / 2748 行） |

基準 80% に対して 2.9pt の余裕がある。新規コード追加時はテストも同時に追加する。

---

## 2. 実装済みの機能

| 領域 | 状態 | 根拠・補足 |
| --- | --- | --- |
| 認証 | 実装済み | 会社コード + login_id/email + パスワード（bcrypt）。`Accounts.Auth` と `AuthController` による実装。仮ユーザー（pending）→ 管理者承認。 |
| アカウント状態 | 実装済み | `pending` / `active` / `suspended` / `anonymized`。停止・匿名化アクションと Oban 日次匿名化。 |
| 管理者の承認 UI | 実装済み | `/admin/pending-users`。admin のみ。 |
| ユーザー削除方針 | 実装済み | 物理削除せず `suspended` → 30日後に `anonymized`。設計は `DESIGN_USER_DELETION.md`。 |
| チケット | 実装済み | 一覧（フィルタ/ソート/ページング）・新規作成・詳細。`public_id`、楽観ロック、関連タスクの紐付け。 |
| チケット状態遷移 | 実装済み | `new`〜`closed` の許可遷移、タイムスタンプ更新、`status_changed` イベント。 |
| チケット認可 | 一部実装 | `Ash.Policy.Authorizer` で `update` / `set_status` / `destroy` を制御。read/create は全許可。 |
| チケットチャット | 実装済み | 公開（`internal_public`）と内部メモ（`internal_private`）。依頼者以外の社外ユーザーには内部メモ非表示。 |
| チャット/イベントのページング | 実装済み | チケット詳細で 20 件ずつ「もっと読む」。 |
| イベントログ | 実装済み | `ticket_events`（作成・状態変更・メッセージ投稿・検証登録）。詳細画面で表示。 |
| 検証・承認 | 一部実装 | `resolved` のみ検証登録可。結果は passed/failed/needs_review。admin/leader が `verified` / `closed` へ遷移可能。 |
| 通知 | 実装済み | resolved / 検証登録時に admin/leader 宛の通知を Oban で生成。`/notifications` で受信者別一覧・未読件数・既読化。 |
| 問い合わせ（Inquiry） | 実装済み | `/inquiries/new` から送信し、Ticket を自動生成。製品選択・依頼者指定・サーバ側検証・テナント検証を含む。 |
| 製品マスタ | 実装済み | `/products` で作成・編集・有効化/無効化。チケット・問い合わせでは有効な製品のみ選択可能。 |
| タスク | 実装済み | 一覧・作成・詳細・編集・削除、優先度変更（`set_priority`）と履歴表示。担当者の company 検証付き。 |
| チケット関連リンク | 実装済み | チケット詳細から関連/再起票/重複/依存を登録・解除。`/relations` で Sigma.js の関係グラフを俯瞰表示。 |
| ダッシュボード | 一部実装 | `/` にチケット・タスク・製品・通知の概要と最近の項目を表示。分析・レポートは未実装。 |
| レート制限・攻撃耐性 | 実装済み | Hammer / PlugAttack / RemoteIp。 |
| 基盤 | 実装済み | Oban、Cachex、Telemetry、Docker（PostgreSQL 18）、CI（test / quality / dialyzer / assets）。 |
| テスト | 実装済み | ExUnit 160 件 + PropCheck 13 プロパティ（StateM / FSM / negative を含む）。 |
| ドキュメント | 実装済み | 要件・設計メモ・運用手順・Walkthrough。 |

---

## 3. 未実装・部分実装（ギャップ）

### 3.1 MVP を閉じるために必要なもの


### 3.2 品質・セキュリティ

- **カバレッジの余裕は 2.9pt**（82.9% / 基準 80%）。新規コード追加時はテストを同時に追加する。
- **ツールチェーンは固定済み**（`.tool-versions`: Erlang 29.1.2 / Elixir `ref:v1.20.4`）。CI も同一バージョン。
- **企業（テナント）境界は company 単位に統一済み**
  - チケット一覧・詳細は自社 company の範囲に制限（`visibility_scope: "global"` は全体公開として例外）。
  - 担当者・投稿者の候補は自社の内部ユーザーに限定。
  - タスクは自社 company のみ。社外ユーザーは `/tasks` からリダイレクト。
  - ユーザー承認は管理者の自社 company の pending ユーザーのみ。
  - admin/leader の特権操作は「ロール + 対象チケットの company 一致」で制約。
- **会社境界は Ash multitenancy と actor スコープで二重に担保**
  - 主要リソースに `strategy :attribute` / `attribute :company_id` / `global? true` の multitenancy を設定。
  - `Tenancy.Scope` が tenant または actor の company_id で read を絞り、`Tenancy.Guard` が越境 write を拒否する。
  - Domain の会社スコープ付きクエリは tenant を渡す。actor なしのシステム処理は従来どおり動作する。
- 通知は同一チケット・種別・受信者につき既定 5 分のクールダウンで抑制する（`NOTIFICATION_COOLDOWN_SECONDS` で変更可）。
- **通知 read は受信者に限定済み**。`TicketNotification` の Preparation と read/mark_read ポリシーで保証。
- **暗号化対象はメール・会社名・表示名・本文系まで完了**。残りは鍵ローテーションと暗号化列の全文検索方針。
- `code_interface`、Domain API、aggregates、Ash multitenancy は導入済み。
  - 差分には `ticket_notifications` / `ticket_verifications` の作成、`tasks` / `task_events` の `company_id` 追加、
    旧 `ticket_messages` テーブルの DROP が含まれる。
  - 既存 DB に適用するには手動レビューが必要なため、自動生成・適用はしていない。

### 3.3 フェーズ 3 以降

- P1 かつ SEV=P1 の全体公開候補と手動承認
- 添付ファイル、ウイルススキャン、保存先設計
- ダッシュボードの分析機能、レポート、統計
- 監視連携、SSO、会話チャット連携（通知のメール/Webhook は実装済み）
- LiquidAI D1 / D1 Ultra による意思決定支援（フェーズ7）
- JSON API（`DESIGN_API_MIGRATION.md` は設計のみ）

---

## 4. ドキュメントと実装の乖離

`README.md` の「主な機能」と「ロードマップ」には、実装済みと読めるが実際は未実装の項目が含まれていた。

| README の記載 | 実際 |
| --- | --- |
| 問い合わせ受付 → チケット自動生成 | バックエンドのみ。Web フォーム未実装 |
| チケット一覧/詳細（フィルタ/ソート） | フィルタ/ソート未実装 |
| SLA 管理 | 実装済み（優先度別目標・達成/逸脱判定・設定画面・ダッシュボード集計） |
| 担当者自動アサイン | 未実装 |
| タスクの CRUD 操作 | 作成・更新・削除 UI も実装済み |
| ユーザー管理 | 仮ユーザー承認画面のみ |
| ダッシュボード / レポート | 簡易ダッシュボードは実装済み。レポートは未実装 |
| ユーザー認証（AshAuthentication） | `ash_authentication` の部品は使うが、認証フローは `Accounts.Auth` の独自実装 |

本レポート作成時に README の該当箇所を実態に合わせて修正し、[ROADMAP.md](ROADMAP.md) へリンクした。

---

## 5. 参照

- 要件: [REQUIREMENTS.md](REQUIREMENTS.md)
- ロードマップ: [ROADMAP.md](ROADMAP.md)
- 未完了タスク: Backlog.md（`backlog/`、`backlog task list --plain`）
- 実装計画: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
- 未決定事項: [UNDECIDED_ITEMS.md](UNDECIDED_ITEMS.md)
- 作業履歴: [Walkthrough.md](Walkthrough.md)
- テスト方針: [TESTING.md](TESTING.md)
