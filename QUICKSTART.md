# 🚀 クイックスタートガイド

## 現在の状態

✅ **完了済み**
- Phoenix + Ash Framework プロジェクト作成
- Docker環境構築（PostgreSQL 16）
- データベース作成・マイグレーション実行
- Makefile による開発コマンド整備

## 📦 セットアップ済みの内容

### 1. プロジェクト構成
```
helpdesk_commander/
├── lib/
│   ├── helpdesk_commander/         # ビジネスロジック層
│   │   ├── application.ex          # アプリケーションスーパーバイザー
│   │   ├── mailer.ex               # メール送信
│   │   └── repo.ex                 # AshPostgres Repo
│   └── helpdesk_commander_web/     # Web層
│       ├── components/             # 再利用可能なコンポーネント
│       ├── controllers/            # コントローラー
│       ├── endpoint.ex             # HTTPエンドポイント
│       ├── router.ex               # ルーティング
│       └── telemetry.ex            # メトリクス収集
├── docker/                         # Docker関連ファイル
│   └── postgres/
│       ├── Dockerfile              # PostgreSQL Dockerfile
│       └── init.sql                # DB初期化スクリプト
├── docker-compose.yml              # Docker Compose設定
├── Makefile                        # 開発用コマンド
└── README.md                       # 詳細ドキュメント
```

### 2. インストール済みの技術スタック

- **Ash Framework 3.0** - リソース管理フレームワーク
- **AshPostgres 2.0** - PostgreSQLデータレイヤー
- **AshPhoenix 2.0** - Phoenix統合
- **Phoenix LiveView 1.1.0** - リアルタイムUI
- **Tailwind CSS 4.1.12** - スタイリング
- **Credo 1.7** - コード品質チェック
- **Dialyxir 1.4** - 静的型チェック

### 3. Docker環境

PostgreSQLがDocker上で稼働中：
- **ポート**: 5432
- **ユーザー**: postgres
- **パスワード**: postgres
- **データベース**: helpdesk_commander_dev

## 🎯 次のステップ

### Phase 1: リソース作成（今ここ！）

#### A. タスク管理リソース

```bash
# タスクドメインを作成
mkdir -p lib/helpdesk_commander/tasks

# Task リソースを作成
touch lib/helpdesk_commander/tasks/task.ex

# User リソースを作成
touch lib/helpdesk_commander/tasks/user.ex

# ドメイン定義を作成
touch lib/helpdesk_commander/tasks.ex
```

#### B. ヘルプデスクリソース

```bash
# ヘルプデスクドメインを作成
mkdir -p lib/helpdesk_commander/helpdesk

# Ticket リソースを作成
touch lib/helpdesk_commander/helpdesk/ticket.ex

# Inquiry リソースを作成
touch lib/helpdesk_commander/helpdesk/inquiry.ex

# ドメイン定義を作成
touch lib/helpdesk_commander/helpdesk.ex
```

#### C. マイグレーション生成

```bash
# Ashマイグレーションを生成
make ash-migrate
# または
mix ash_postgres.generate_migrations --name add_initial_resources

# マイグレーション実行
make db-migrate
```

### Phase 2: UI実装

```bash
# LiveView作成
mkdir -p lib/helpdesk_commander_web/live/task_live
mkdir -p lib/helpdesk_commander_web/live/ticket_live

# タスク一覧ページ
touch lib/helpdesk_commander_web/live/task_live/index.ex
touch lib/helpdesk_commander_web/live/task_live/index.html.heex

# チケット一覧ページ
touch lib/helpdesk_commander_web/live/ticket_live/index.ex
touch lib/helpdesk_commander_web/live/ticket_live/index.html.heex
```

### Phase 3: ルーティング設定

`lib/helpdesk_commander_web/router.ex` にルートを追加：

```elixir
scope "/", HelpdeskCommanderWeb do
  pipe_through :browser

  # ダッシュボード
  live "/", DashboardLive, :index

  # タスク管理
  live "/tasks", TaskLive.Index, :index
  live "/tasks/new", TaskLive.Index, :new
  live "/tasks/:id/edit", TaskLive.Index, :edit

  # ヘルプデスク
  live "/tickets", TicketLive.Index, :index
  live "/tickets/new", TicketLive.Index, :new
  live "/tickets/:id", TicketLive.Show, :show
end
```

## 🛠 よく使うコマンド

```bash
# サーバー起動
make server

# データベース操作
make db-create     # DB作成
make db-migrate    # マイグレーション実行
make db-reset      # DBリセット
make db-seed       # シードデータ投入

# Docker操作
make docker-up     # PostgreSQL起動
make docker-down   # PostgreSQL停止
make docker-logs   # ログ確認

# 開発
make test          # テスト実行
make format        # コードフォーマット
make credo         # コード品質チェック
make dialyzer      # 型チェック（要: make dialyzer-plt）

# ヘルプ
make help          # 全コマンド表示
```

## 🔍 動作確認

### 1. サーバー起動

```bash
cd /Users/atsushi/elixir/helpdesk_commander
make server
```

### 2. ブラウザでアクセス

- メインページ: http://localhost:4000
- LiveDashboard: http://localhost:4000/dev/dashboard
- メールボックス: http://localhost:4000/dev/mailbox

### 3. データベース接続確認

```bash
# iex起動
make iex

# Repo確認
iex> HelpdeskCommander.Repo.__adapter__()
# => Ecto.Adapters.Postgres

# データベース接続確認
iex> Ecto.Adapters.SQL.query!(HelpdeskCommander.Repo, "SELECT version()")
```

## 📚 参考リンク

- [Ash Framework Documentation](https://hexdocs.pm/ash/readme.html)
- [AshPostgres Guide](https://hexdocs.pm/ash_postgres/readme.html)
- [Phoenix LiveView Guide](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)

## 💡 ヒント

### Ashリソースの基本構造

```elixir
defmodule MyApp.MyDomain.MyResource do
  use Ash.Resource,
    domain: MyApp.MyDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "my_resources"
    repo MyApp.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    timestamps()
  end

  actions do
    defaults [:read, :destroy]
    create :create
    update :update
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
  end
end
```

## 🐛 トラブルシューティング

### PostgreSQLに接続できない

```bash
# コンテナの状態確認
docker ps

# ログ確認
make docker-logs

# 再起動
make docker-down
make docker-up
```

### マイグレーションエラー

```bash
# マイグレーション状態確認
mix ecto.migrations

# 最後のマイグレーションをロールバック
mix ecto.rollback

# データベースをリセット
make db-reset
```

## ✅ チェックリスト

- [x] プロジェクト作成
- [x] Docker環境構築
- [x] データベース作成
- [x] マイグレーション実行
- [ ] タスク管理リソース作成
- [ ] ヘルプデスクリソース作成
- [ ] UI実装
- [ ] 認証機能追加
- [ ] デプロイ準備

---

詳細な情報は [README.md](./README.md) を参照してください。
