---
id: HC-5
title: ダッシュボードの分析機能とレポートを実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-01T15:42:00Z'
labels:
  - p2
  - ui
milestone: m-3
dependencies: []
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
簡易ダッシュボードはあるが、未対応・滞留・負荷の分析やレポート出力がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 未対応件数・滞留時間・担当者別負荷を集計できる
- [x] #2 期間指定で集計できる
- [x] #3 画面または CSV で出力できる
- [x] #4 集計クエリのテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Analytics モジュールで期間内のチケットを集計する（未対応・未着手・滞留24h超・平均滞留時間・状態別・優先度別・担当者別負荷）。2. ダッシュボードに期間指定フォームと分析セクションを追加する。3. 同じ集計を CSV で返すコントローラを追加する。4. 集計ロジックと画面・CSV をテストする。5. docs と検証結果を更新する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Analytics モジュールを追加し、期間内に作成されたチケットの未対応・未着手・滞留（既定24時間超）・平均滞留時間・状態別・優先度別・担当者別負荷を集計する。期間は from/to の日付（UTC、終了日を含む）で指定する。ダッシュボードに期間指定フォーム、指標カード、担当者別テーブル、状態/優先度別リストを追加した。同じ集計を /reports/analytics.csv から CSV ダウンロードできる（社内ユーザーのみ）。
検証: analytics_test 4 passed、dashboard_live_test 5 passed（追加2件）、report_controller_test 4 passed、mix precommit 272 passed（13 properties / 259 tests）、coveralls 83.1%（2385 / 2868 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
未対応件数・未着手・滞留24h超・平均滞留時間・状態別・優先度別・担当者別負荷を集計する Analytics を追加した。ダッシュボードで期間（開始日/終了日）を指定して集計でき、同じ内容を CSV としてダウンロードできる。外部ユーザーには分析と CSV を公開しない。検証は analytics_test 4件、dashboard_live_test の追加2件、report_controller_test 4件、mix precommit 272 passed（13 properties / 259 tests）、coveralls 83.1%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
