# 認証スタックの判断（HC-12）

タスク HC-12「AshAuthentication への一本化を判断・実施する」の結論と差分整理。

## 結論

**AshAuthentication への一本化は行わない。現行の独自 `HelpdeskCommander.Accounts.Auth` を維持する。**

- サインイン・ユーザー登録・承認は `Accounts.Auth`（`lib/helpdesk_commander/accounts/auth.ex`）と
  `User` リソースのアクション（`register` / `set_password` / `approve` / `set_login_id` 等）で完結している。
- `ash_authentication` 依存は mix.exs に存在したが、アプリケーションコードからは一度も参照されていない
  （未使用依存）。本タスクで削除した。
- SSO（HC-9）は `ash_authentication` を間に挟まず、その下層ライブラリである **Assent を直接使って
  OIDC を実装する**。既存セッション基盤（Cookie セッション + `AuthController`、API は HC-11 の
  `AuthToken` Bearer）と同じ形に接続できる。

## 現行実装の特徴（差分整理の前提）

| 領域 | 現行実装 |
| --- | --- |
| マルチテナント | `company_id` 属性 strategy。認証は「会社コード → `company_code_hash` 検索 → 会社内でユーザー特定」の 2 段階 |
| ユーザー特定 | `login_id`（32 文字まで、社内ユニーク）またはメール。メールは cloak 暗号化 + `email_hash` の HMAC 索引で検索 |
| パスワード | Bcrypt。`password_hash` は `register` / `set_password` アクションで直接更新 |
| 状態遷移 | `pending`（承認待ち）→ `active` → `suspended` / `anonymized`。承認は管理者の `approve` |
| 承認フロー | `register_pending_user`（pending ユーザーへパスワード設定）+ `approve_user`。AshAuthentication の自動登録・確認アドオンでは表現しづらい |
| email ログイン | `login_id` を持つユーザーの email ログインは禁止（`email_login_disabled`）、初回 email ログイン時に login_id を自動生成 |
| anonymize | 個人情報を cloak で上書きし `email_hash`・`login_id`・`password_hash` を無効化 |

## AshAuthentication との機能差分

| 項目 | AshAuthentication（Password strategy） | 現行 Auth | 影響 |
| --- | --- | --- | --- |
| サインインの照合キー | `username_attribute` 単一（通常 email） | 会社コード ×（login_id or email_hash） | 2 テナント構造が標準と噛み合わない。strategy の read を差し替える工数 ≫ 自作維持コスト |
| パスワードハッシュ | 独自の hash ライフサイクル（生成・トークン等） | Bcrypt 直書き + `HashPassword` 変更 | 既存ハッシュの互換維持が必要 |
| テナントスコープ | `tenant` オプションは Ash クエリに効くが company_code ハッシュでの前段検索は独自実装 | `Tenancy.Scope` / `Tenancy.Guard` + 会社検索 | 移行時に Tenancy ガードの再検証が必須 |
| 承認ワークフロー | なし（add-on の confirmation は email confirm 用） | `pending` ステータス + `approve` | 承認フローはどちらにせよ差し替え対象でない |
| セッション | AshAuthentication のトークン/JWT が前提 | Phoenix Cookie セッション（user_id）+ `AuthToken`（API 用 Phoenix.Token） | セッション機構を 2 系統化するリスク |
| OIDC/OAuth | strategy あり（下層は Assent） | なし（HC-9 で Assent 直接使用） | SSO のみ差分。Assent 直接使用で同等機能を持たせられる |

## 判断の理由

1. 差分の大半は AshAuthentication 側で標準化されていない部分（ cloak された PII キーによる照合、
   会社コード前段検索、承認フロー）であり、一本化しても strategy の差し替えが必要。
2. 既存テストは 326 件中、承認・サスペンド・anonymize・login_id 自動生成まわりが認証基盤と密接に
   結合している。移行で再検証対象が広く、機能上の恩恵（password / confirmation strategy）が小さい。
3. SSO 導入（HC-9）に必要なのは OIDC クライアントであって認証フレームワークの全面移行ではない。
   Assent を直接使えば既存セッションにそのまま接続できる。

## 将来的に一本化する場合の移行手順

再評価の契機は「AshAuthentication のアドオン（confirmation・API 認証等）が複数必要になった場合」。
その場合の手順は:

1. strategy 設計: `Password` strategy のサインイン read を自前の `company_code` × `email_hash` /
   `login_id` 照合アクションへ差し替える（`get_by` ではなくカスタム `sign_in` アクション）。
2. ユーザー属性のマッピング: `User` に `username` 互換属性を設けるか、strategy の照合キーを
   `email_hash` に寄せる。
3. 段階移行: HC-11 と同様に「API で先行、UI は既存」の順にする。`AuthController` のサインインを
   strategy 経由に置換し、Cookie セッションの扱いは現行のまま維持する。
4. 影響テスト: 認証系（承認・サスペンド・login_id・email ログイン禁止）＋ HC-11 API 認証
   ─ 全実行での回帰確認。
