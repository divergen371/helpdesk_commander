---
id: HC-39
title: 変異テストを高リスクモジュールに限定して CI に導入する
status: Done
assignee: []
created_date: '2026-11-07T11:30:00Z'
updated_date: '2026-11-07T17:03:00Z'
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
- [x] #1 対象モジュール（例: Accounts.Auth / Attachments / Authorization）と実行トリガー（PR 差分 or 定期）を決める
- [x] #2 CI での実行時間上限（例: 10 分）と失敗条件（mutation score の下限）を決める
- [x] #3 等価・許容する mutant は # mutare:ignore と理由で管理する
- [x] #4 検出されたテスト不足を解消するか、許容理由を記録する
- [x] #5 docs に実行方法・しきい値・除外方針を記載する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
対象: Authorization / Attachments.FilePolicy / Support.PiiHash / Support.CompanyCode の 4 モジュール。PR は MUTATION_SINCE=origin/<base> で変更行のみ、main push と夜間は全量。CI ジョブのタイムアウト 15 分、下限は各 95%（現在はすべて 100%）。全量実行は約 8 分。
実装: priv/ci/run_mutation.sh（モジュール・下限の一覧、--since 対応）、ci.yml に mutation job（fetch-depth 0、summary 対象に追加）、quality-nightly.yml に全量実行を追加。
等価 mutant: Authorization の privileged_role?/external? の guard_drop、same_company? の not is_nil、PiiHash の 3 つの guard_drop、CompanyCode の 3 つの guard_drop を理由付き # mutare:ignore で管理。
テスト不足の解消: PII 正規化の trim/downcase、認可の非バイナリ・会社不一致、FilePolicy の大文字拡張子/MIME パラメータ/前後空白/10MB 境界/欠損ファイル/upload 以外、CompanyCode.hash! のメッセージ。テストは 425 -> 438 件に増加。
検証: bash priv/ci/run_mutation.sh が 4 モジュールすべて 100% で成功（全量 約8分）。mix precommit 451 passed（13 properties / 438 tests）、coveralls 82.59%（3699/4479）、sobelow 0、依存監査 ok。
docs: QUALITY_MUTATION.md（対象・しきい値・トリガー・ignore 方針・追加手順）、QUALITY_GATES / CI_CD / ROADMAP / STATUS を更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
変異テストを高リスク 4 モジュール（Authorization / FilePolicy / PiiHash / CompanyCode）に限定して CI に導入した。PR は変更行のみ（--since origin/<base>）、main push と夜間は全量を実行し、各モジュール 95% 未満で失敗する（現在はすべて 100%、全量で約 8 分、ジョブ上限 15 分）。等価な mutant は理由付き # mutare:ignore で管理し、検出されたテスト不足（PII 正規化、認可の非バイナリ・会社不一致、形式検証の境界、例外メッセージ）はテストを追加して解消した。mix precommit 451 passed（13 properties / 438 tests）、coveralls 82.59%、sobelow 0、依存監査 ok。
<!-- SECTION:FINAL_SUMMARY:END -->
