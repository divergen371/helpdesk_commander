# Implementation Plan

このドキュメントは「実装計画」を記録し、作業進行に合わせて更新する。
実装後に判明したこと（できた/できなかった・懸念点）は末尾に追記する。

## 目的
- MVPで「問い合わせ→チケット→対応→検証→承認」の運用を成立させる
- 監査性・堅牢性・性能を満たす基盤（イベント/会話ログ、通知、レート制限）を整備する

## 現状
- コアリソース（Users/Tickets/Tasks）と `public_id` 方針は実装済み
- Oban / Cachex / Telemetry / Hammer / PlugAttack / RemoteIp を導入済み
- Inquiry は実装済み（自動 Ticket 生成まで。Web フォームは未実装）
- Conversation / Event 系のリソースを実装済み（ページング基盤含む）
- Task 優先度履歴 UI と `set_priority` 導線を実装済み（CRUD UI は未実装）
- Ticket の `set_status` / `update` 権限制御は Policy Authorizer に移行済み
- 通知は `ticket_notifications` への保存まで実装済み（UI・既読導線は未実装）
- 検証・承認フロー、製品マスタ、チケット関連リンクのリソースを実装済み
- 2026-10-24 時点の検証結果・ギャップ・リスクは [STATUS.md](STATUS.md) に整理
- フェーズ別の残作業と優先順位は [ROADMAP.md](ROADMAP.md)、詳細タスクは [TASKS.md](TASKS.md) を参照

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

## 実装後メモ（2026-10-24 現状調査 / OTP 29・Elixir 1.20 対応）

- `main` / `a25dc83` を対象に、実装・テスト・CI・ドキュメントの現状を調査
- **Erlang/OTP 29.1.2 + Elixir 1.20.4 へ更新**
  - `.tool-versions` に Erlang/Elixir を固定し、CI も同一バージョンへ更新
  - Ash 3.37.0 / AshPostgres 2.15.1 / AshPhoenix 2.3.25、Phoenix 1.8.16 / LiveView 1.2.13 へ更新
  - `config :ash, default_string_length_count: :codepoints` を追加（Ash 3.37 の必須設定）
  - Elixir 1.20 の型推論警告に対応（`CurrentUser.id/1`、`<.button>` の `type` 属性許可）
- `mix precommit` 成功（13 properties / 111 tests / 0 failures、Credo 指摘なし、警告 0）
- `MIX_ENV=test mix coveralls` は **80.0%** で基準を満たす
  - `CurrentUser` / `Authorization` / 認証コントローラのテストを追加して回復
- 旧環境（OTP 28.3 + Elixir 1.19.4）では `yamerl` の再コンパイル問題があったが、
  OTP 29 + 更新後依存 + クリーンな rebar3 設定では解消
- `mix ash.codegen --check` は 8 ファイルの生成待ちを報告（既存の snapshot 未更新）
  - `ticket_messages` の DROP を含むため、自動適用せず `TASKS.md` に手動レビュー項目として追加
- 実装と README の記述に乖離があったため、README の機能一覧とロードマップを実態に合わせて修正
- 新規ドキュメント:
  - `docs/STATUS.md`（現状・検証結果・ギャップ・リスク）
  - `docs/ROADMAP.md`（フェーズ別ロードマップ・優先バックログ・マイルストーン）
- `docs/TASKS.md` を現状に合わせて更新

## 実装後メモ（2026-10-24 テナント境界・認可監査 / 通知 read）

- テナント境界を company 単位に統一
  - チケット一覧・詳細は自社 company に制限（`global` 公開のみ例外）
  - 担当者・投稿者候補、ユーザー承認、サンプルユーザー作成を自社 company に限定
  - タスクは社外ユーザーを `/tasks` からリダイレクト
  - `Ticket` の特権操作はロールに加えて対象チケットの company 一致を要求
  - `Task.set_priority` は実行者とタスクの company 一致を要求
- `TicketNotification` に受信者限定の read Preparation を追加
  - `recipient_id == actor.id` で絞り込み、`inserted_at desc` に統一
  - read / mark_read の Ash ポリシーを追加
- テストを追加（横断的なテナント境界、社外タスク拒否、通知の受信者分離・既読拒否）
- `mix precommit` 成功、13 properties / 122 tests、カバレッジ 80.3%

## 実装後メモ（2026-10-25 Inquiry Web フォーム）

- `/inquiries/new` を追加（ログイン必須）
  - 製品マスタから対象製品を選択
  - 社外ユーザーは依頼者を自分に固定
  - 内部ユーザーは自社 company のユーザーを依頼者として選択
- Inquiry の入力検証
  - subject 1..200、body 1..10,000
  - 前後空白をトリムし、空文字を拒否
  - 製品・依頼者の company 一致をリソース側でも検証
  - `company_id` はフォームから受け取らず依頼者から導出
- 送信後は自動生成された Ticket 詳細へ遷移
- チケット一覧に「問い合わせ」導線を追加
- 共通フォームオプション（ユーザー/製品）を `HelpdeskCommanderWeb.FormOptions` に抽出
- テスト追加
  - 社外/内部の問い合わせ送信、トリム、空入力、別会社製品・依頼者の拒否、未ログインリダイレクト
- `mix precommit` 成功、13 properties / 130 tests、カバレッジ 80.5%

## 実装後メモ（2026-10-25 チケット一覧フィルタ/ソート/ページング）

- `/tickets` にフィルタ・ソート・ページングを追加
  - 状態 / 優先度 / 種別 / 担当者
  - 並び順: 新しい順 / 古い順 / 優先度順 / ステータス順
  - URL クエリで条件を保持（例: `/tickets?status=resolved&page=2`）
- 20件単位の offset ページング
  - 総件数・現在ページ・前へ/次へ
  - `stream(:tickets, ..., reset: true)` で更新
- 一覧に種別・担当者列を追加
- 担当者フィルタ用に `FormOptions.load_internal_users/1` を追加
- テスト追加（フィルタ、担当者、ソート、21件ページング）
- `mix precommit` 成功、13 properties / 133 tests、カバレッジ 80.9%

## 実装後メモ（2026-10-25 通知 UI）

- `/notifications` を追加（ログイン必須）
  - 受信者本人の通知のみ表示（既存 Preparation / ポリシーを利用）
  - 未読件数、通知一覧、チケットへの導線
  - 個別既読と一括既読
- `HelpdeskCommander.Helpdesk.Notifications` に通知操作を集約
  - `list_for/1` / `unread_count/1` / `mark_read/2` / `mark_all_read/1`
- チケット一覧に通知ボタンと未読件数を表示
- テスト追加（受信者分離、既読、一括既読、非受信者拒否、未読件数）
- `mix precommit` 成功、13 properties / 139 tests、カバレッジ 81.1%

## 実装後メモ（2026-10-25 タスク CRUD UI）

- `/tasks/new` とタスク詳細の編集フォームを追加
  - タイトル / 説明 / ステータス / 期限 / 担当者
  - 優先度は `set_priority` と履歴表示に分離
- タスク削除を追加
  - `task_events` の FK を `ON DELETE CASCADE` に変更
- 入力検証とテナント検証
  - タイトル 1..200、説明 10,000 文字以内、status/priority allowlist
  - 前後空白トリム
  - 担当者が同一 company のユーザーであることを検証
- `Task.update` から priority を外し、楽観ロックを追加
- テスト追加（作成・編集・削除・バリデーション・担当者テナント・event cascade）
- `mix precommit` 成功、13 properties / 145 tests、カバレッジ 81.3%

## 実装後メモ（2026-10-25 チケットとタスクの紐付け）

- `ticket_task_links` を追加
  - 同一 company のチケット・タスクのみ紐付け
  - 重複拒否、チケット/タスク削除時はカスケード削除
- チケット詳細に関連タスクセクションを追加（内部ユーザーのみ）
  - 紐付け済みタスクの表示、未紐付けタスクの追加、解除
- テスト追加（LiveView、テナント境界、重複、カスケード）
- `mix precommit` 成功、13 properties / 152 tests、カバレッジ 81.2%
