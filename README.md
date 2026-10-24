# Helpdesk Commander

[![CI](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml/badge.svg)](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml)

Phoenix LiveView と Ash Framework を使用した **タスク管理 & ヘルプデスク統合システム**

## 📋 概要

Helpdesk Commanderは、社内のタスク管理とヘルプデスク業務を1つのアプリケーションで管理できる統合システムです。

## 📄 要件定義

- 要件・運用フロー（問い合わせ→チケット→検証→承認、障害管理の段階導入など）は以下を参照してください。
  - [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)

### 主な機能

実装状況の詳細は [docs/STATUS.md](docs/STATUS.md)、今後の予定は [docs/ROADMAP.md](docs/ROADMAP.md) を参照してください。

#### 🎯 タスク管理

- タスクの一覧・詳細表示（作成/編集/削除 UI は未実装）
- ステータス管理（未着手/進行中/完了）
- 優先度設定（低/中/高）と変更履歴
- 期限設定
- 担当者アサイン

#### 🎫 ヘルプデスク

- 問い合わせ受付（Inquiry リソースと Ticket 自動生成。Web フォームは未実装）
- チケット管理（一覧/新規作成/詳細）
- チケットチャット（公開/非公開）
- チケット状態遷移とイベントログ
- 検証・承認フロー（resolved → 検証 → verified/closed）
- 優先度・担当者の確定（管理者/リーダーのみ）
- アプリ内通知の保存（通知 UI は未実装）
- チケット関連リンクのリソース（UI は未実装）
- SLA 管理（未実装・設計のみ）

#### 👥 共通機能

- 会社・ユーザー認証と仮ユーザー承認
- ユーザーの停止・匿名化
- リアルタイム更新（Phoenix LiveView）
- ダッシュボード / レポート（未実装）

## 🛠 技術スタック

- **Elixir**: 1.20.4
- **Erlang/OTP**: 29.1.2
- **Phoenix**: 1.8.3
- **Phoenix LiveView**: 1.1.0
- **Ash Framework**: 3.0
- **AshPostgres**: 2.0
- **AshPhoenix**: 2.0
- **PostgreSQL**: 18 (Docker)
- **Oban**: 2.x（ジョブ処理）
- **Cachex**: 4.x（インメモリキャッシュ）
- **Telemetry**: 1.x（計測）
- **Hammer**: 7.x（レート制限）
- **PlugAttack**: 0.4.x（不正アクセス対策）
- **RemoteIp**: 1.x（プロキシ配下のIP補正）
- **Tailwind CSS**: 4.1.12
- **Credo**: 1.7 (コード品質チェック)
- **Dialyxir**: 1.4 (静的型チェック)

## 🚀 クイックスタート

### 前提条件

- Elixir 1.15以上
- Erlang/OTP 29.1.2 以上（`.tool-versions` を参照）
- Docker & Docker Compose
- Make（オプション）

### 1. リポジトリのクローン

```bash
cd /Users/atsushi/elixir/helpdesk_commander
```

### 2. 初期セットアップ

#### Makeを使う場合（推奨）

```bash
make setup
```

これで以下が自動実行されます：

- 依存関係のインストール
- PostgreSQLコンテナの起動
- データベースの作成
- マイグレーションの実行

#### 手動セットアップ

```bash
# 依存関係のインストール
mix deps.get

# PostgreSQLコンテナの起動
docker-compose up -d postgres

# データベースの作成
mix ecto.create

# マイグレーションの実行
mix ecto.migrate
```

### 3. サーバーの起動

```bash
# Makeを使う場合
make server

# または直接
mix phx.server

# iexで起動する場合
make iex
# または
iex -S mix phx.server
```

アプリケーションは [http://localhost:4000](http://localhost:4000) で起動します。

## 📁 プロジェクト構造

```
helpdesk_commander/
├── lib/
│   ├── helpdesk_commander/
│   │   ├── tasks/              # タスク管理ドメイン
│   │   │   ├── task.ex         # タスクリソース
│   │   │   └── user.ex         # ユーザーリソース
│   │   ├── helpdesk/           # ヘルプデスクドメイン
│   │   │   ├── ticket.ex       # チケットリソース
│   │   │   ├── inquiry.ex      # 問い合わせリソース
│   │   │   └── assignment.ex   # アサインメントリソース
│   │   └── repo.ex             # AshPostgres Repo
│   └── helpdesk_commander_web/
│       └── live/
│           ├── task_live/      # タスク管理UI
│           └── ticket_live/    # ヘルプデスクUI
├── docker/
│   └── postgres/
│       ├── Dockerfile          # PostgreSQL Dockerfile
│       └── init.sql            # 初期化SQL
├── docker-compose.yml          # Docker Compose設定
├── Makefile                    # 開発用コマンド
└── README.md                   # このファイル
```

## 🐳 Docker関連コマンド

```bash
# PostgreSQLコンテナの起動
make docker-up

# コンテナの停止
make docker-down

# ログの確認
make docker-logs

# ボリュームを含めて完全削除
make docker-clean
```

## 💾 データベース操作

```bash
# データベース作成
make db-create

# マイグレーション実行
make db-migrate

# データベースリセット
make db-reset

# シードデータ投入
make db-seed

# Ashマイグレーション生成
make ash-migrate
```

## 🧧 開発コマンド

```bash
# テスト実行
make test

# コードフォーマット
make format

# Credo静的解析
make credo
make credo-strict  # 厳格モード

# Dialyzer型チェック
make dialyzer-plt   # PLT生成（初回のみ）
make dialyzer       # 型チェック実行

# ビルドファイル削除
make clean

# 利用可能なコマンド一覧
make help
```

## ✅ テスト戦略（詳細）

このプロジェクトのテストは、以下を組み合わせています。

- 通常のユニット/統合テスト（ExUnit）
- 性質ベーステスト（PropCheck）
  - ネガティブテスト
  - Stateful Property（StateM）
  - Finite State Machine Property（FSM）

基本コマンド:

```bash
# 全テスト
mix test

# PBT対象のみ（主要）
mix test \
  test/helpdesk_commander/support/public_id_propcheck_test.exs \
  test/helpdesk_commander/accounts/user_state_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_status_fsm_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_status_negative_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_verification_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_authorization_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_notification_propcheck_test.exs \
  --seed 0

# 反例キャッシュをクリア（必要時）
MIX_ENV=test mix propcheck.clean
```

運用ルール:

- `mix precommit` を最終確認として実行してください（本プロジェクトの標準）
- PBTは乱択なので、再現が必要な場合は `--seed` を固定してください
- FSMプロパティのみ `store_counter_example: false` を設定しています（失敗を成功に変えるものではなく、反例保存による循環を避けるため）

詳細は以下を参照:

- [docs/TESTING.md](docs/TESTING.md)

## 🔧 設定

### データベース接続

開発/テスト用のDB接続は **環境変数で上書き可能** です（デフォルトはローカル開発向けの `postgres/postgres`）。

推奨（URLで指定）:

```bash
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/helpdesk_commander_dev
export TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/helpdesk_commander_test
```

URLを使わない場合（個別指定）:

```bash
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
```

## 📚 Ashフレームワークについて

Ashは宣言的なElixir用リソースフレームワークで、以下の利点があります：

- **宣言的なリソース定義**: スキーマ、アクション、バリデーションを一箇所で管理
- **自動CRUD操作**: 基本的なCRUD操作を自動生成
- **リレーションシップ管理**: belongs_to、has_manyなどを簡単に定義
- **ポリシー管理**: 認可ルールをリソースレベルで定義
- **拡張性**: カスタムアクションやバリデーションを追加可能

### リソース定義例

```elixir
defmodule HelpdeskCommander.Tasks.Task do
  use Ash.Resource,
    domain: HelpdeskCommander.Tasks,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tasks"
    repo HelpdeskCommander.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :description, :string
    attribute :status, :atom, default: :todo
    attribute :priority, :atom, default: :medium
    timestamps()
  end

  relationships do
    belongs_to :user, HelpdeskCommander.Tasks.User
  end

  actions do
    defaults [:read, :destroy]
    create :create
    update :update
  end
end
```

## 🗺 ロードマップ

フェーズ別の詳細・受け入れ条件・優先バックログは [docs/ROADMAP.md](docs/ROADMAP.md)、
現時点の実装状況と課題は [docs/STATUS.md](docs/STATUS.md) を参照してください。

### フェーズ1（MVP）: 受付〜チケット運用の基盤 — 🟡 一部実装

- [x] プロジェクトセットアップ
- [x] Docker環境構築（PostgreSQL 18）
- [x] タスク管理リソース作成
- [x] ヘルプデスクリソース作成（Inquiry/Ticket/Conversation/Event）
- [ ] Inquiry Webフォーム（問い合わせ受付・ログイン必須）→ チケット自動生成
- [ ] チケット一覧のフィルタ/ソート/ページング
- [x] チケットチャット（公開/非公開）
- [x] ステータス更新（new/triage/in_progress/waiting/resolved…）
- [x] イベントログ（監査・タイムラインの基盤）
- [ ] 通知 UI（保存は実装済み）
- [ ] タスク CRUD UI（一覧/詳細/優先度履歴は実装済み）

### フェーズ2: 認証/権限・優先度・検証/承認フロー — 🟡 一部実装

- [x] 会社・ユーザー認証（会社コード + login_id/email、仮ユーザー承認）
- [x] 権限管理（優先度変更・最終承認はリーダー/管理者のみ）
- [ ] 優先度（Impact×Urgency）の算出とSLA
- [x] 検証（一般ユーザーも可能）と最終承認（リーダー/管理者のみ）
- [ ] テナント境界・Ash ポリシーの横展開
- [ ] PII 暗号化

### フェーズ3: 障害管理（Incident）

- [ ] Ticket→Incident 昇格/降格（リーダー/管理者のみ）
- [ ] SEV（重大度）
- [ ] 障害タイムライン（調査/暫定対応/復旧/監視/振り返り）

### フェーズ4: コラボレーション強化

- [x] コメント（公開/内部メモ）
- [ ] コメントの編集・削除
- [ ] ファイル添付機能
- [ ] 通知 UI・重複抑制・外部通知

### フェーズ5: 分析・レポート

- [ ] ダッシュボード
- [ ] レポート機能
- [ ] SLA監視
- [ ] 統計情報

### フェーズ6: 外部連携

- [ ] 監視連携
- [ ] チャット連携
- [ ] SSO対応
