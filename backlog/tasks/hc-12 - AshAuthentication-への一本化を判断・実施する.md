---
id: HC-12
title: AshAuthentication への一本化を判断・実施する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:25:00Z'
updated_date: '2026-11-03T10:16:00Z'
labels:
  - p2
  - security
milestone: m-1
dependencies: []
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
認証は独自の Accounts.Auth で実装されている。ash_authentication 依存との差異を整理し、一本化するか判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 現行 Auth と AshAuthentication の機能差分を整理する
- [x] #2 一本化する場合の移行手順と影響範囲を決める
- [x] #3 既存のログイン/登録/承認テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現行 Auth（独自実装）と AshAuthentication の機能差分を整理して docs/AUTH_STACK.md に記録する。2. 判断: 独自 Auth を維持し一本化しない（会社コード×PII ハッシュ×cloak×承認フローが AshAuthentication の標準 strategy と噛み合わず、移行コストが既存 326 テストとセッション基盤へのリスクに見合わない）。SSO は HC-9 で Assent を直接使う。3. 未使用の ash_authentication 依存を削除し deps.unlock。4. 認証系テスト（accounts/auth 関連）を全実行して回帰がないことを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
差分整理: docs/AUTH_STACK.md に現行 Auth と AshAuthentication の機能差分（照合キー、cloak とPII ハッシュ、承認フロー、セッション機構）を記録。
判断: 一本化しない。会社コード × email_hash × cloak × 承認フローは AshAuthentication の標準 strategy では表現できず、移行コストが既存テスト 326 件とセッション基盤へのリスクに見合わない。SSO（HC-9）は下層ライブラリ Assent を直接使う。将来的に一本化する場合の移行手順も同 docs に記載。
実施: 未使用の ash_authentication を mix.exs から削除し deps.unlock。docs の STATUS.md・QUICKSTART.md の記載も更新。
検証: mix compile --warnings-as-errors 成功。accounts/auth 関連テスト 52 passed（1 property / 51 tests）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AshAuthentication への一本化は判断の結果「行わない」とした。現行の Accounts.Auth 独自実装は会社コード × email_hash（cloak+HMAC） × 承認フローなど AshAuthentication の標準 strategy で表現できない要素を含み、移行コストが恩恵を上回る。SSO は HC-9 で Assent を直接使用する。未使用だった ash_authentication 依存を削除し、差分整理と将来の移行手順を docs/AUTH_STACK.md に記録した。認証系テスト 52 件（1 property 含む）が引き続き通ることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
