-- PostgreSQL初期化スクリプト

-- 必要な拡張機能を有効化
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";

-- 開発用データベース
CREATE DATABASE helpdesk_commander_dev;

-- テスト用データベース
CREATE DATABASE helpdesk_commander_test;
