# Helpdesk Commander

[![CI](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml/badge.svg)](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml)

Phoenix LiveView と Ash Framework を使用した **タスク管理 & ヘルプデスク統合システム**

## 📋 概要

Helpdesk Commanderは、社内のタスク管理とヘルプデスク業務を1つのアプリケーションで管理できる統合システムです。

## 📄 要件定義

- 要件・運用フロー（問い合わせ→チケット→検証→承認、障害管理の段階導入など）は以下を参照してください。
  - [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)

### 主な機能

#### 🎯 タスク管理
- タスクのCRUD操作
- ステータス管理（未着手/進行中/完了）
- 優先度設定（低/中/高）
- 期限設定
- 担当者アサイン

#### 🎫 ヘルプデスク
- 問い合わせ受付（ログイン必須）
- チケット自動生成
- チケット管理（オープン/対応中/解決済/クローズ）
- チケットチャット（公開/非公開）
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

詳細な段階導入の方針は [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) を参照してください。

### フェーズ1（MVP）: 受付〜チケット運用の基盤
- [x] プロジェクトセットアップ
- [x] Docker環境構築
- [ ] タスク管理リソース作成
- [ ] ヘルプデスクリソース作成（Inquiry/Ticket/Assignment/Conversation）
- [ ] Webフォーム（問い合わせ受付・ログイン必須）→ チケット自動生成
- [ ] チケット一覧/詳細（フィルタ/ソート）
- [ ] チケットチャット（公開/非公開）
- [ ] ステータス更新（new/triage/in_progress/waiting/resolved…）
- [ ] イベントログ（監査・タイムラインの基盤）
- [ ] 基本UI実装

### フェーズ2: 認証/権限・優先度・検証/承認フロー
- [ ] ユーザー認証（AshAuthentication）
- [ ] 権限管理（優先度変更・最終承認はリーダー/管理者のみ）
- [ ] 優先度（Impact×Urgency）とSLAの初期設計
- [ ] 検証（一般ユーザーも可能）と最終承認（リーダー/管理者のみ）

### フェーズ3: 障害管理（Incident）
- [ ] Ticket→Incident 昇格/降格（リーダー/管理者のみ）
- [ ] SEV（重大度）
- [ ] 障害タイムライン（調査/暫定対応/復旧/監視/振り返り）

### フェーズ4: コラボレーション強化
- [ ] コメント機能
- [ ] ファイル添付機能
- [ ] 通知機能（まずはアプリ内→将来チャット連携へ）

### フェーズ5: 分析・レポート
- [ ] ダッシュボード
- [ ] レポート機能
- [ ] SLA監視
- [ ] 統計情報

### フェーズ6: 外部連携
- [ ] 監視連携
- [ ] チャット連携
- [ ] SSO対応
