---
id: HC-25
title: YARA ルールによる組織固有の検知を追加する
status: To Do
assignee: []
created_date: '2026-11-03T09:14:00Z'
labels:
  - security
  - quality
milestone: m-1
dependencies:
  - HC-22
  - HC-23
priority: medium
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ClamAV の汎用シグネチャでは、自社固有の phishing 文書・マクロ・社内ツールを装う検体を拾いにくい。YARA ルールを版管理して追加し、組織固有の検知を足せるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 YARA ルールをリポジトリで版管理し、スキャナから読み込める
- [ ] #2 ルール一致時は infected として隔離し、一致ルール名を scan_note に記録する
- [ ] #3 ルール更新時に既存添付を再スキャンできる
- [ ] #4 良性ファイルとルール一致ファイルのテストがある
- [ ] #5 ルール追加・更新手順を docs に記載する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
