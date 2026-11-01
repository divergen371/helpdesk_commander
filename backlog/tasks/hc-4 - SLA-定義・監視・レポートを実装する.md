---
id: HC-4
title: SLA 定義・監視・レポートを実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-01T11:49:00Z'
labels:
  - p2
  - ops
milestone: m-3
dependencies: []
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
優先度ごとの一次応答・暫定対応・解決・復旧の目標時間が未定義。遅延を検知して可視化する必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 優先度ごとの SLA 目標を設定できる
- [x] #2 チケットの経過時間から達成/逸脱を判定できる
- [x] #3 ダッシュボードで逸脱件数を確認できる
- [x] #4 SLA 判定のテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SlaPolicy リソース（company × priority の目標分数）と既定値を追加し、未設定時は既定値で補う。2. Sla モジュールで一次応答・暫定対応・解決・復旧の達成/逸脱/未達を判定する（暫定対応と復旧は Incident タイムラインを使用）。3. 管理者/リーダー向けの SLA 設定画面を追加し、優先度ごとの目標分数を編集できるようにする。4. ダッシュボードに SLA 逸脱件数を表示する。5. 判定ロジック・設定保存・ダッシュボードをテストし、docs と検証結果を更新する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: SlaPolicy リソース（company × priority、一次応答/暫定対応/解決/復旧の目標分数）を追加し、未設定時は既定値（P1: 15/60/240/480 分など）で補完する。Sla モジュールで first_response_at / resolved_at と Incident タイムライン（mitigation / recovery）から達成・逸脱・未達・対象外を判定する。管理者/リーダー向け /settings/sla を追加し、優先度ごとに目標を保存できる。ダッシュボードに未クローズチケットの SLA 逸脱件数と該当チケットを表示する。
検証: sla_test 9 passed、sla_live_test 3 passed、mix precommit 262 passed（13 properties / 249 tests）、coveralls 82.9%（2279 / 2748 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
優先度ごとの SLA 目標（一次応答・暫定対応・解決・復旧）を SlaPolicy として保存できるようにし、未設定時は既定値を使う。チケットの経過時間と Incident タイムラインから達成/逸脱/未達を判定し、/settings/sla で管理者/リーダーが目標を編集、ダッシュボードで未クローズチケットの逸脱件数を確認できるようにした。検証は sla_test 9件、sla_live_test 3件、mix precommit 262 passed（13 properties / 249 tests）、coveralls 82.9%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
