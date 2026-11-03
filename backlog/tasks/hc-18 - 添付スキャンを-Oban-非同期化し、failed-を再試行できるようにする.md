---
id: HC-18
title: 添付スキャンを Oban 非同期化し、failed を再試行できるようにする
status: To Do
assignee: []
created_date: '2026-11-03T09:10:00Z'
labels:
  - security
  - quality
  - ops
milestone: m-1
dependencies:
  - HC-16
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スキャンをアップロード処理内で同期実行しているため、大きなファイルやスキャナのハングで LiveView が待たされる。Oban の非同期ジョブへ移し、失敗時の再試行と手動再スキャンを可能にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 アップロードは pending を返し、スキャンは Oban ジョブで実行される
- [ ] #2 failed は上限付きの指数バックオフで再試行される
- [ ] #3 管理者またはアップロード者が手動で再スキャンできる
- [ ] #4 同じ添付が二重にスキャンされない冪等性がある
- [ ] #5 非同期実行・再試行・二重実行防止のテストがある
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
