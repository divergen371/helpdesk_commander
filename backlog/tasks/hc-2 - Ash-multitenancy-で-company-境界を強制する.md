---
id: HC-2
title: Ash multitenancy で company 境界を強制する
status: To Do
assignee: []
created_date: '2026-11-01T08:24:00Z'
labels:
  - p2
  - security
milestone: m-1
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
company 境界は現在 Domain クエリのフィルタで維持している。API 化や新規画面の追加時に漏れが起きやすいため、Ash の multitenancy で強制する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 company_id を tenant として Ash の multitenancy を設定する
- [ ] #2 既存の会社スコープ付きクエリが tenant 前提で動作する
- [ ] #3 越境アクセスが拒否されるテストがある
- [ ] #4 既存テストとカバレッジ基準を維持する
<!-- AC:END -->
