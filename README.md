# Helpdesk Commander

[![CI](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml/badge.svg)](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml)

Phoenix LiveView と Ash Framework を使用した **タスク管理 & ヘルプデスク統合システム**

## 📋 概要

Helpdesk Commanderは、社内のタスク管理とヘルプデスク業務を1つのアプリケーションで管理できる統合システムです。

### 主な機能

#### 🎯 タスク管理
- タスクのCRUD操作
- ステータス管理（未着手/進行中/完了）
- 優先度設定（低/中/高）
- 期限設定
- 担当者アサイン

#### 🎫 ヘルプデスク
- 問い合わせ受付
- チケット自動生成
- チケット管理（オープン/対応中/解決済/クローズ）
- 優先度設定（低/中/高/緊急）
- 担当者自動アサイン
- SLA管理

#### 👥 共通機能
- ユーザー管理
- ダッシュボード
- リアルタイム更新（Phoenix LiveView）
- レポート機能

## 🛠 技術スタック

- **Elixir**: 1.19.4
- **Erlang/OTP**: 28.3
- **Phoenix**: 1.8.3
- **Phoenix LiveView**: 1.1.0
- **Ash Framework**: 3.0
- **AshPostgres**: 2.0
- **AshPhoenix**: 2.0
- **PostgreSQL**: 16 (Docker)
- **Tailwind CSS**: 4.1.12
- **Credo**: 1.7 (コード品質チェック)
- **Dialyxir**: 1.4 (静的型チェック)

## 🚀 クイックスタート

### 前提条件

- Elixir 1.15以上
- Erlang/OTP 26以上
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

## 📊 データベーススキーマ

### users テーブル

| カラム名     | 型        | 説明               |
|-------------|----------|-------------------|
| id          | uuid     | 主キー             |
| name        | string   | ユーザー名         |
| email       | string   | メールアドレス     |
| role        | string   | ロール（admin/agent/user）|
| inserted_at | datetime | 作成日時           |
| updated_at  | datetime | 更新日時           |

### tasks テーブル

| カラム名     | 型        | 説明                          |
|-------------|----------|------------------------------|
| id          | uuid     | 主キー                        |
| title       | string   | タスク名                      |
| description | text     | タスクの説明                   |
| status      | string   | ステータス                     |
| priority    | string   | 優先度                        |
| due_date    | date     | 期限                          |
| user_id     | uuid     | 担当者ID                      |
| inserted_at | datetime | 作成日時                       |
| updated_at  | datetime | 更新日時                       |

### tickets テーブル

| カラム名      | 型        | 説明                          |
|--------------|----------|------------------------------|
| id           | uuid     | 主キー                        |
| subject      | string   | 件名                          |
| description  | text     | 詳細                          |
| status       | string   | ステータス                     |
| priority     | string   | 優先度                        |
| requester_id | uuid     | 問い合わせ者ID                 |
| assignee_id  | uuid     | 担当者ID                      |
| closed_at    | datetime | クローズ日時                   |
| inserted_at  | datetime | 作成日時                       |
| updated_at   | datetime | 更新日時                       |

## 🔧 設定

### データベース接続

`config/dev.exs` でデータベース接続情報を設定：

```elixir
config :helpdesk_commander, HelpdeskCommander.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "helpdesk_commander_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

環境変数で上書きも可能：

```bash
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/helpdesk_commander_dev
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

### Phase 1: 基本機能（現在）
- [x] プロジェクトセットアップ
- [x] Docker環境構築
- [ ] タスク管理リソース作成
- [ ] ヘルプデスクリソース作成
- [ ] 基本UI実装

### Phase 2: 高度な機能
- [ ] ユーザー認証（AshAuthentication）
- [ ] 権限管理
- [ ] ファイル添付機能
- [ ] コメント機能
- [ ] 通知機能

### Phase 3: 分析・レポート
- [ ] ダッシュボード
- [ ] レポート機能
- [ ] SLA監視
- [ ] 統計情報
