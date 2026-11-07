---
id: HC-38
title: 変異テスト（mix mutant）の導入可否を評価する
status: Done
assignee: []
created_date: '2026-11-07T10:48:00Z'
updated_date: '2026-11-07T11:32:00Z'
labels:
  - quality
  - p3
milestone: m-1
dependencies: []
priority: low
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テストの「量」はカバレッジで測れるが「検出力」は測れていない。mix mutant で 1 モジュールを対象に試験実行し、実行時間・検出されるテスト不足・CI への組み込みコストを評価して採否を決める。実装は行わず、判断と次タスクの提案までにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 対象モジュールと実行範囲を決め、1 モジュールで試験実行する
- [x] #2 実行時間と CI への影響を見積もる
- [x] #3 検出されたテスト不足の例を記録する
- [x] #4 採否の判断と理由を docs に残し、採用時の次タスクを提案する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
評価: mutare 0.5 を dev/test に追加（sourceror 1.13.0 -> 1.12.4 の制約調整が必要）。候補（mutare / Muex / mutalisk / muta）を比較し、compile-once と --since を持つ mutare を採用して試験。
試験: lib/helpdesk_commander/support/company_code.ex で 37 mutants / killed 32 / survived 5 / score 86.5% / 約 55 秒。survivors は guard_drop（非バイナリ入力のテストなし）3 件とエラーメッセージ文字列 2 件で、具体的なテスト不足を確認できた。
判断: lib 全体の一括実行は Ash マクロの変換失敗と実行時間の面で不適。CI へは高リスク領域（認証・添付・権限）に限定し、PR 差分またはモジュール指定で導入する。フォローアップ HC-39 を作成。
ドキュメント: docs/QUALITY_MUTATION.md に候補比較・試験結果・実行方法・判断を記録。依存と手順は再現可能な形で残した。
検証: mutare 実行結果（上記）、mix quality / sobelow / audit / coverage ratchet はすべて成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
変異テストを評価した。mutare（compile-once）を 1 モジュール（company_code.ex）で試験し、37 mutants・score 86.5%・約 55 秒で、ガード削除とエラーメッセージ未検証という具体的なテスト不足を検出した。全 lib の一括実行は Ash マクロの変換失敗と実行時間の面で不適と判断し、CI へは高リスク領域に限定して PR 差分またはモジュール指定で導入する方針とした（HC-39）。候補比較・結果・実行方法・判断は docs/QUALITY_MUTATION.md に記録。
<!-- SECTION:FINAL_SUMMARY:END -->
