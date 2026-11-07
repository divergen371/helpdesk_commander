---
id: HC-39
title: 変異テストを高リスクモジュールに限定して CI に導入する
status: To Do
assignee: []
created_date: '2026-11-07T11:30:00Z'
labels:
  - quality
  - ci
  - p2
milestone: m-1
dependencies:
  - HC-38
priority: medium
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HC-38 の評価で、mutare は 1 モジュール（company_code.ex）を 55 秒・37 mutants・score 86.5% で実行でき、guard_drop とエラーメッセージの未検証を検出した。一方、lib 全体では Ash マクロの変換に失敗し、全モジュールを CI で回すのは時間・安定性の両面で現実的でない。対象を認証・添付・権限など高リスク領域に限定し、PR の差分（--since）かモジュール指定で CI に組み込む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 対象モジュール（例: Accounts.Auth / Attachments / Authorization）と実行トリガー（PR 差分 or 定期）を決める
- [ ] #2 CI での実行時間上限（例: 10 分）と失敗条件（mutation score の下限）を決める
- [ ] #3 等価・許容する mutant は # mutare:ignore と理由で管理する
- [ ] #4 検出されたテスト不足を解消するか、許容理由を記録する
- [ ] #5 docs に実行方法・しきい値・除外方針を記載する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
