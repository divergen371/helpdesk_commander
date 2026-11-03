# SSO（OIDC）設計 — HC-9

方式は **OIDC（Authorization Code Flow）** に決定した。Assent の `Assent.Strategy.OIDC` を直接使う
（AshAuthentication を間に挟まない理由は `AUTH_STACK.md` を参照）。SAML は Elixir 側の実装資産が
弱く、社内 IdP は OIDC 対応が一般的なため見送り。

## ログインフロー

1. `GET /auth/sso/start/:company_code`
   - 会社コードで会社を確認し、`Assent.Strategy.OIDC.authorize_url/1` で IdP へリダイレクト
   - state / nonce（16 バイトのランダム値）をセッション `:sso` に保存（会社コードも一緒に保存）
2. IdP で認証 → `GET /auth/sso/callback?code=...&state=...`
   - Assent が code 交換・state 検証・ID Token 検証（署名・iss / aud / exp / nonce）まで実行
   - ID Token の claims から `email` を取り出し、会社内で `email_hash` 照合してユーザーを特定
3. ユーザーが存在する場合は既存のステータス判定（active はログイン、pending / suspended /
   anonymized は拒否メッセージ）、存在しない場合は自動プロビジョニング
4. ログイン時はパスワードログインと同じセッション方式（`configure_session(renew: true)` +
   `put_session(:user_id)`）

## 設定（runtime.exs、環境変数）

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `SSO_ENABLED` | false | `1`/`true`/`yes` 等で有効化 |
| `SSO_ISSUER_URL` | なし | OIDC issuer（base_url）。有効化には必須 |
| `SSO_CLIENT_ID` / `SSO_CLIENT_SECRET` | なし | IdP に登録したクライアント |
| `SSO_REDIRECT_URI` | `http://localhost:4000/auth/sso/callback` | 基点 URI |
| `SSO_COMPANY_CODE` | `A-000001` | サインイン画面の SSO ボタンのターゲット会社 |
| `SSO_AUTO_PROVISION` | `pending` | 未登録ユーザーの自動作成。`pending` / `active` / 無効は `false` |
| `SSO_ROLE_CLAIM` | `groups` | ロール判定に使う claim 名 |
| `SSO_ADMIN_GROUP` | なし | claim のリストに一致する値があればロール `admin`、なければ `user` |
| `SSO_DISPLAY_NAME_CLAIM` | `name` | 表示名の取得元 claim |

## 会社・ロールのマッピング

- 会社: start の `:company_code`（または設定の `SSO_COMPANY_CODE`）で固定。メールの
  ドメイン判定は行わない（複数 IdP・複数会社の運用は start URL で分岐する）
- ロール: `SSO_ROLE_CLAIM`（既定 `groups`）のリストの中に `SSO_ADMIN_GROUP` があれば
  `admin`、そうでなければ `user`
- 表示名: `SSO_DISPLAY_NAME_CLAIM`（既定 `name`）→ email のローカル部 → `SSO ユーザー` の順

## テスト

`HelpdeskCommander.SSOStubHTTPAdapter`（`test/support/`）が IdP を擬似する。Assent の
`http_adapter` 設定にスタブを注入し、openid-configuration と token endpoint の応答、HS256 署名の
ID Token（固定 nonce）を返す。state / nonce 検証・自動プロビジョニング・ロールマッピング・
ステータス拒否を 9 件のコントローラテストで確認する。
