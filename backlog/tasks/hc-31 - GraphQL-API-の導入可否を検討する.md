---
id: HC-31
title: GraphQL API の導入可否を検討する
status: To Do
assignee: []
created_date: '2026-11-07T10:31:00Z'
labels:
  - integration
dependencies: []
priority: low
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JSON API v1（/api/v1、Bearer 認証）は HC-11 で実装済み。GraphQL は必要になった段階で検討する方針のまま ROADMAP に残っており、判断材料が未整理。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GraphQL を必要とする具体的な利用者・用途があるか確認する
- [ ] #2 JSON API v1 との差分（取得柔軟性・実装/運用コスト）を比較する
- [ ] #3 採用/不採用の判断と理由を docs に残す
- [ ] #4 採用する場合の次タスク（スキーマ・認可・テスト）を提案する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
