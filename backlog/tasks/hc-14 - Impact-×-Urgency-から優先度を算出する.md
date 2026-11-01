---
id: HC-14
title: Impact × Urgency から優先度を算出する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:25:00Z'
updated_date: '2026-11-01T10:29:00Z'
labels:
  - p2
  - quality
milestone: m-1
dependencies: []
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
impact / urgency は保持しているが、優先度の自動算出がない。DESIGN_PRIORITY_CHECK.md を前提に算出ルールを決めて実装する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Impact × Urgency の算出表を確定する
- [x] #2 チケット作成/更新時に優先度を算出できる
- [x] #3 手動変更との優先順位ルールを決める
- [x] #4 算出ロジックのテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Priority モジュールに Impact/Urgency の値集合と 4x4 算出表を実装する。2. Ticket に priority_source（auto/manual）を追加し、impact/urgency 変更時に自動算出、明示的な priority 指定時は manual として優先する Change を create/update に適用する。3. チケット作成・詳細画面に Impact/Urgency の入力と表示を追加し、優先度は「自動」を選べるようにする。4. 算出表と自動/手動の切替をテストする。5. migration・snapshot・docs を更新し、precommit/coverage/dialyzer/codegen で検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: HelpdeskCommander.Helpdesk.Priority に 4x4 の算出表（widespread/significant/moderate/minor × critical/high/medium/low）を追加。Ticket に priority_source（auto/manual）を追加し、ComputePriority Change を create/update に適用した。明示的に priority を指定した操作は manual として優先し、impact/urgency の変更時は算出表で再計算する。作成画面の優先度入力は廃止し、Impact/Urgency のみ申告させる。詳細画面では管理者/リーダーが Impact/Urgency/Priority を更新できる。
検証: priority_test 9 passed、priority_live_test 2 passed、mix precommit 250 passed（13 properties / 237 tests）、coveralls 82.5%（2131 / 2582 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Impact × Urgency の 4x4 算出表を実装し、チケット作成・更新時に優先度を自動算出するようにした。明示的な優先度指定は manual として尊重し、impact/urgency の変更時は再計算する。priority_source で由来を保持し、作成画面は Impact/Urgency の申告のみ、確定操作は管理者/リーダーに限定した。検証は priority_test 9件、priority_live_test 2件、mix precommit 250 passed（13 properties / 237 tests）、coveralls 82.5%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
