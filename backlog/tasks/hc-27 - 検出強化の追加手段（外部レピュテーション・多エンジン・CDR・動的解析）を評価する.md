---
id: HC-27
title: 検出強化の追加手段（外部レピュテーション・多エンジン・CDR・動的解析）を評価する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-03T09:14:00Z'
updated_date: '2026-11-14T15:40:00Z'
labels:
  - security
  - ai
  - integration
milestone: m-1
dependencies:
  - HC-26
priority: low
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ClamAV 単体では未知のマルウェアや標的型文書の検出力に限界がある。外部レピュテーション、多エンジン、CDR、動的解析を比較し、PII・コスト・運用負荷を含めて採用可否を決める。実装は行わない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 外部レピュテーション、多エンジン、CDR、動的解析の候補を比較する
- [x] #2 ファイル送信の有無を含む PII・機密性の影響を評価する
- [x] #3 コスト・レイテンシ・運用負荷を比較する
- [x] #4 採用/不採用の判断と理由を決定ログに残す
- [x] #5 実装は行わず、次タスクの提案までにする
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現行の添付検査（ClamAV + YARA + マジックバイト + ハッシュ規則 + サンドボックス）の限界を整理する。2. 4 領域（外部レピュテーション・多エンジン・CDR・動的解析）の候補を比較し、ファイル送信有無（PII/機密性）・コスト・レイテンシ・運用負荷を評価する。3. 採用/不採用の判断と理由を決定ログ（docs/DECISION_DETECTION_METHODS.md と backlog decision）に記録する。4. 実装は行わず、採用候補の次タスクを提案し、ROADMAP / STATUS を更新して PR を作成する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
比較: docs/DECISION_DETECTION_METHODS.md に 4 領域（ハッシュ照合型レピュテーション / ファイル送信型レピュテーション・多エンジン / CDR / 動的解析）の候補、ファイル送信の有無、PII・機密性、コスト、レイテンシ、運用負荷、実装コストを整理。価格・SLA はベンダー見積が必要であることを明記。
決定: decision-1（accepted）。ハッシュ照合（SHA256 のみ、ファイル送信なし）を採用し HC-41 を起票。オンプレミス CDR は PoC（HC-42）。ファイル送信を伴う多エンジン・動的解析は既定で見送り、再検討条件（顧客同意・DPA・専用テナント・オンプレ・高リスク限定）を記録。
実装なし: コード変更はなし。次タスク HC-41 / HC-42 を Backlog に登録。ROADMAP / STATUS を更新。
検証: docs のみの変更。mix quality 451 passed（13 properties / 438 tests）、dialyzer 0、codegen OK、coveralls 82.59%、sobelow 0。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ClamAV 単体の限界を補う追加手段を評価し、決定を記録した。外部レピュテーションはファイル本体を送らない SHA256 照合を採用（HC-41）、オンプレミス CDR は PoC（HC-42）、ファイル送信を伴う多エンジンと動的解析は PII 方針と両立しないため既定で見送り、再検討条件を明記した。決定は decision-1 と docs/DECISION_DETECTION_METHODS.md に残し、実装は行っていない。
<!-- SECTION:FINAL_SUMMARY:END -->
