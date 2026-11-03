---
id: HC-11
title: JSON API 化を実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:25:00Z'
updated_date: '2026-11-03T10:07:00Z'
labels:
  - p2
  - integration
milestone: m-3
dependencies:
  - HC-2
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Web UI のみで、外部システムから操作する API がない。DESIGN_API_MIGRATION.md を前提に実装する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 認証方式とバージョニングを決定する
- [x] #2 主要リソースの CRUD API を実装する
- [x] #3 ポリシーと会社境界が API でも強制される
- [x] #4 OpenAPI または仕様ドキュメントを用意する
- [x] #5 API テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. /api/v1 を追加し、Phoenix.Token による Bearer 認証と既存セッションの両方を許可する。2. サインイン・自分情報・製品一覧・チケット一覧/作成/詳細/更新を実装する。3. actor と tenant を必ず渡し、Ash ポリシーと multitenancy で会社境界を強制する。外部ユーザーは自分のチケットのみ。4. エラーは code/message/fields の統一形式、楽観ロック競合は 409。5. OpenAPI 仕様を JSON で公開し、API テストを追加する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: /api/v1 を追加した。認証は Phoenix.Token の Bearer（既存 Cookie セッションも許容）。サインイン、自分の情報、製品一覧、チケット一覧/作成/詳細/更新/ステータス変更/公開コメント一覧を実装。actor と tenant を必ず渡し、Ash ポリシーと multitenancy で会社境界を強制。外部ユーザーは自分が依頼者のチケットのみ。優先度・担当者はポリシーにより一般ユーザーは変更不可。楽観ロック競合は 409、バリデーションは 422 の統一エラー形式。OpenAPI 3.0 仕様を /api/v1/openapi.json で公開。
検証: api_test 11 passed、mix precommit 339 passed（13 properties / 326 tests）、coveralls 81.9%（3126 / 3814 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
JSON API v1 を薄い Phoenix コントローラとして実装した。認証は Phoenix.Token の Bearer トークン（既存セッションも許容）、バージョンはパス /api/v1。チケットの一覧・作成・詳細・更新・ステータス変更と公開コメント、製品一覧を公開し、actor と tenant で会社境界を強制する。外部ユーザーは自分のチケットのみ、優先度・担当者の確定は Ash ポリシーに従う。楽観ロック競合は 409、OpenAPI 仕様は /api/v1/openapi.json。検証は API テスト 11件、mix precommit 339 passed（13 properties / 326 tests）、coveralls 81.9%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
