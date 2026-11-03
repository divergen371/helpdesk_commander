---
id: HC-9
title: SSO（OIDC/SAML）を導入する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-03T10:38:00Z'
labels:
  - p2
  - security
milestone: m-3
dependencies: []
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
会社コード + login_id の認証のみで、社内 IdP との SSO がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OIDC または SAML の方式を決定する
- [x] #2 IdP のユーザーを会社・ロールへマッピングできる
- [x] #3 既存ログインと併存または移行方針が決まっている
- [x] #4 認証テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 方式は OIDC（Authorization Code Flow、state/nonce 検証）に決定。SAML はエコシステムが弱く社内 IdP は OIDC 対応が一般的なため見送り。2. Assent を依存に明示追加し、Assent.Strategy.OIDC で /auth/sso/start/:company_code → /auth/sso/callback を実装（既存セッション方式: put_session(:user_id) と同一経路）。3. ユーザーは email_hash で会社内照合。未登録は SSO_AUTO_PROVISION（pending/active/false）に従い自動作成。ロールは SSO_ROLE_CLAIM + SSO_ADMIN_GROUP による claim マッピング。4. テストはスタブ HTTP アダプタを Assent 設定に注入して IdP を擬似（openid config / token / id_token は HS256 署名）。5. サインイン画面に SSO ボタン、docs 更新。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: OIDC（Authorization Code Flow）を Assent（Assent.Strategy.OIDC）で実装。/auth/sso/start/:company_code と /auth/sso/callback を追加。state・nonce はセッションに保存して Assent が検証。
ユーザー照合: ID Token の claims の email を会社内で email_hash 照合。ステータス判定（active / pending / suspended / anonymized）はパスワードログインと同じメッセージ。
プロビジョニング: 未登録は SSO_AUTO_PROVISION（pending / active / false）に従い作成。ロールは SSO_ROLE_CLAIM（既定 groups）に SSO_ADMIN_GROUP があれば admin。
設定: runtime.exs に SSO_* 環境変数群。サインイン画面に SSO ボタン（enabled 時）。設計は docs/DESIGN_SSO.md。
テスト: アダプタを注入するスタブ IdP（openid-configuration / token / HS256 の ID Token、固定 nonce）で 9 件。全 SSO フロー＋不正 state・email なし等。
検証: sso_controller_test 9 passed。mix precommit 348 passed（13 properties / 335 tests）、coveralls 82.0%（3229 / 3935 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
方式は OIDC（Authorization Code Flow）に決定し、Assent の Strategy.OIDC で実装した。SAML は見送り（Elixir 資産の弱さと社内 IdP の OIDC 対応が理由）。IdP との接続は /auth/sso/start → callback で Assent が state・nonce・ID Token を検証。ユーザーは email_hash で会社内照合し、ステータス判定は既存ログインと同じ。未登録ユーザーは SSO_AUTO_PROVISION（pending 既定）で自動作成し、groups claim + SSO_ADMIN_GROUP で admin へマッピング。テストはスタブ IdP（Assent の http_adapter 注入、HS256 の固定 nonce ID Token）で 9 件。mix precommit 348 passed（13 properties / 335 tests）、coveralls 82.0%、dialyzer 0 errors。
<!-- SECTION:FINAL_SUMMARY:END -->
