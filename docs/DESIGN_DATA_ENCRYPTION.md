# データ暗号化設計メモ（AshCloak + 検索ハッシュ）

## 目的
- 事象説明、チャット本文、ユーザー名（表示名）、会社名、メールアドレスなどの機微情報を「DB流出時に平文で読めない」状態にする。
- ただし、認証・検索・一意制約（特にメールアドレス）は維持し、運用を壊さない。

## 前提
- 現状は `users.email` / `companies.name` が平文で保存され、`users.email` は認証で等価検索に利用している。
- `users.password_hash` は bcrypt ハッシュであり、これは暗号化対象ではない（現状維持）。

## 保護対象の分類
### A. 検索・一意制約が必要な項目（暗号化 + 検索用ハッシュ）
- `users.email`
- `companies.name`

### B. 主に表示用途の本文系（暗号化中心）
- `tickets.description`（事象説明）
- `inquiries.body`
- `conversation_messages.body`（チャット本文）
- `users.display_name`（本名が入る可能性）

## 方式
### 1) 暗号化本体
- `ash_cloak` を利用して保存時に暗号化、読出し時に復号する。
- アプリケーションの論理属性（例: email）は維持しつつ、DB物理カラムは `*_enc` に段階移行する。

### 2) 検索・一意制約
- 検索が必要な項目は、正規化後の値に対して HMAC-SHA256 を計算し `*_hash` に保存する。
- 例: `email_hash = HMAC_SHA256(secret, normalize(email))`
- 一意制約と検索は `*_hash` に対して実施する。

## スキーマ方針（案）
### users
- 追加:
  - `email_enc`（暗号化本体）
  - `email_hash`（検索・UNIQUE用）
  - `display_name_enc`（暗号化本体）
- インデックス:
  - `unique_index(:users, [:company_id, :email_hash])`
- 認証:
  - `Auth.fetch_user/2` の email 検索は `normalize(email)` → `email_hash` で照合。

### companies
- 追加:
  - `name_enc`
  - `name_hash`
- インデックス:
  - `unique_index(:companies, [:name_hash])`

### tickets / inquiries / conversation_messages
- 追加:
  - `tickets.description_enc`
  - `inquiries.body_enc`
  - `conversation_messages.body_enc`
- 検索要件が後で必要になった場合のみ `*_hash` を追加する（初期は不要）。

## 段階導入手順
1. 依存追加と設定
   - `:ash_cloak` を追加、鍵管理（環境変数/secret manager）を設定。
2. 追加マイグレーション
   - `*_enc` / `*_hash` カラムと新インデックスを追加（既存カラムは残す）。
3. バックフィル
   - 既存平文を暗号化列・ハッシュ列へ移送。
4. アプリ切替（互換期間）
   - write: 新旧二重書き（短期間）
   - read: 新カラム優先、未移行レコードは旧カラムフォールバック
5. 完全移行
   - 認証・検索を hash ベースに統一
   - 旧平文カラムを削除

## 運用・セキュリティ要件
- 鍵はリポジトリに保存しない（環境変数/secret manager経由）。
- 本番ログに平文PIIを出さない（認証失敗ログ、監査ログのマスキングを徹底）。
- バックアップ/ダンプのアクセス制御を維持（暗号化は追加防御であり、権限制御の代替ではない）。

## テスト方針
- 単体:
  - 正規化 + ハッシュ一致
  - 暗号化属性の round-trip（保存→読出し）
- 認証:
  - emailログインが hash 検索へ切替後も通ること
  - company境界で一意制約が維持されること
- 回帰:
  - `mix precommit` で既存機能回帰なしを確認

## 非目標（初期フェーズ）
- 暗号化本文に対する全文検索
- 過去ログの即時完全再暗号化（鍵ローテーションの自動化は次フェーズ）
