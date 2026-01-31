FROM postgres:18-alpine

# PostgreSQL拡張機能のインストール
RUN apk add --no-cache postgresql-contrib

# 初期化スクリプト用のディレクトリ
COPY init.sql /docker-entrypoint-initdb.d/

# デフォルトの文字エンコーディング設定
ENV POSTGRES_INITDB_ARGS="--encoding=UTF8 --locale=ja_JP.UTF-8"
