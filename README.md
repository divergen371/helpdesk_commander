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

- タスクの CRUD 操作（作成・編集・削除）
- ステータス管理（未着手/進行中/完了）
- 優先度設定（低/中/高）と変更履歴
- 期限設定
- 担当者アサイン

#### 🎫 ヘルプデスク

- 問い合わせ受付（`/inquiries/new` から Ticket を自動生成）
- チケット管理（一覧のフィルタ/ソート/ページング、新規作成、詳細）
- チケットチャット（公開/非公開）
- チケット状態遷移とイベントログ
- チケットとタスクの紐付け（チケット詳細から追加・解除）
- 検証・承認フロー（resolved → 検証 → verified/closed）
- Impact × Urgency からの優先度自動算出（手動確定は管理者/リーダーのみ）
- 優先度・担当者の確定（管理者/リーダーのみ）
- 通知（`/notifications` の一覧・未読管理、クールダウン、メール / Slack Webhook 配信）
- チケット関連リンク（登録・解除）と Sigma.js 関係グラフ PoC
- 製品マスタ管理（作成・編集・有効化/無効化）
- SLA 管理（優先度別目標、達成/逸脱判定、設定画面、ダッシュボード集計）

#### 👥 共通機能

- 会社・ユーザー認証と仮ユーザー承認
- ユーザーの停止・匿名化
- リアルタイム更新（Phoenix LiveView）
- 簡易ダッシュボード（チケット・タスク・製品・通知の概要）

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
export DATABASE_URL=postgres://postgres:postgres@localhost:5433/helpdesk_commander_dev
export TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5433/helpdesk_commander_test
```

URLを使わない場合（個別指定）:

```bash
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5433
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
```

`docker-compose.yml` はホスト側 **5433** を既定にしています（5432 が他用途で埋まっている環境向け）。変更する場合は `POSTGRES_HOST_PORT` と `POSTGRES_PORT` を揃えてください。

### PII 暗号化（本番必須）

本番環境では以下の環境変数が必要です。

```bash
# Base64 エンコードした 32 バイト鍵
# elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
export CLOAK_KEY=...
export PII_HMAC_SECRET=...
export COMPANY_CODE_HMAC_SECRET=...
```

`CLOAK_KEY` を失うと暗号化済みのメールアドレス・会社名を復号できません。secret manager で保管してください。

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

未完了タスクは **Backlog.md**（`backlog/`）を正本とし、フェーズの方針は [docs/ROADMAP.md](docs/ROADMAP.md) にまとめています。

```bash
backlog task list --plain   # 未完了タスク
backlog board               # ターミナルの Kanban
backlog browser             # ローカル Web UI
```

- 現在: フェーズ1〜4の主要機能は実装済み（添付ファイル・関連チケットの自動提案は未着手）。関係グラフの調整が残り
- フェーズ5以降: SLA・分析・外部連携・AI 意思決定支援は Backlog.md の M2〜M5 で管理
- テスト・カバレッジの現状は [docs/STATUS.md](docs/STATUS.md)、作業履歴は [docs/Walkthrough.md](docs/Walkthrough.md)
- エージェント向けの運用は [docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md)
