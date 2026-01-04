.PHONY: help docker-up docker-down docker-logs db-create db-migrate db-reset server iex test format setup clean

help: ## このヘルプメッセージを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## 初回セットアップ（依存関係インストール、Docker起動、DB作成）
	mix deps.get
	make docker-up
	sleep 5
	make db-create
	make db-migrate
	@echo "✅ セットアップ完了！'make server' でサーバーを起動できます"

docker-up: ## PostgreSQLコンテナを起動
	docker-compose up -d postgres
	@echo "⏳ PostgreSQLの起動を待っています..."
	@sleep 3

docker-down: ## Dockerコンテナを停止
	docker-compose down

docker-logs: ## Dockerコンテナのログを表示
	docker-compose logs -f postgres

docker-clean: ## Dockerボリュームも含めて完全削除
	docker-compose down -v

db-create: ## データベースを作成
	mix ecto.create

db-migrate: ## マイグレーションを実行
	mix ecto.migrate

db-reset: ## データベースをリセット
	mix ecto.reset

db-seed: ## シードデータを投入
	mix run priv/repo/seeds.exs

server: ## Phoenixサーバーを起動
	mix phx.server

iex: ## iexで起動
	iex -S mix phx.server

test: ## テストを実行
	mix test

format: ## コードをフォーマット
	mix format

credo: ## Credoで静的解析を実行
	mix credo

credo-strict: ## Credoを厳格モードで実行
	mix credo --strict

dialyzer: ## Dialyzerで型チェックを実行
	mix dialyzer

dialyzer-plt: ## Dialyzer PLTファイルを生成/更新
	mix dialyzer --plt

clean: ## ビルドファイルを削除
	mix clean

ash-migrate: ## Ashマイグレーションを生成
	@read -p "マイグレーション名を入力してください: " name; \
	mix ash_postgres.generate_migrations --name $$name
