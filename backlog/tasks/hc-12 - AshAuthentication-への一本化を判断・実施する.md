---
id: HC-12
title: AshAuthentication への一本化を判断・実施する
status: To Do
assignee: []
created_date: '2026-11-01T08:25:00Z'
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
- [ ] #1 現行 Auth と AshAuthentication の機能差分を整理する
- [ ] #2 一本化する場合の移行手順と影響範囲を決める
- [ ] #3 既存のログイン/登録/承認テストが通る
<!-- AC:END -->
