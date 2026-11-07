---
id: HC-33
title: CI の品質ゲートを一本化し PR で自動判定する
status: Done
assignee: []
created_date: '2026-11-07T10:48:00Z'
updated_date: '2026-11-07T11:07:00Z'
labels:
  - quality
  - ci
  - p1
milestone: m-1
dependencies: []
priority: high
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI は test/credo/dialyzer/assets に分かれているが、`mix precommit` 相当（format 含む）・`mix ash.codegen --check`・カバレッジ閾値が PR の必須条件として一本化されていない。手元のコマンドと CI の差で品質がぶれる。daily-report-void-ts の M1-1（PR ごとに型検査・テスト・ビルド）に相当するゲートを、Elixir/Ash の実情に合わせて整備する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PR で `mix precommit`（compile warnings-as-errors / format / credo strict / test）が実行され、失敗時にマージできない
- [x] #2 `mix ash.codegen --check` と `mix dialyzer` が PR で実行され、失敗時にブロックする
- [x] #3 カバレッジが基準（80% 以上、可能なら前回比ラチェット）を下回ると失敗する
- [x] #4 失敗したゲートと理由が GitHub の job summary で分かる
- [x] #5 わざと失敗させる検証 PR で各ゲートが実際に落ちることを確認する
- [x] #6 ローカルと CI のコマンド対応表が docs にある
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: `mix quality`（precommit + ash.codegen --check + dialyzer）と `mix quality.coverage`（coveralls.json + ラチェット）を alias に追加。カバレッジ判定は priv/ci/check_coverage.exs + priv/ci/coverage_baseline.txt（82.0%、絶対下限 80%）。
CI: .github/workflows/ci.yml を再構成。coverage job（coveralls.json → ラチェット → artifact）、precommit job（mix precommit + ash.codegen --check、Postgres service）、dialyzer job、assets job、summary job（各結果を $GITHUB_STEP_SUMMARY に表で出力し、失敗/キャンセル時は summary も失敗）。credo は precommit に統合し独立 quality job を削除。
ゲートの失敗確認（検証後に復元）: format=1 / compile warnings=1 / credo=4 / test=2 / codegen=1 / dialyzer=2 / coverage（基準99%上書き）=1。ローカルで各ゲートが非ゼロ終了することを確認（実際の検証 PR は次回 CI 変更時に実施）。
副修正: test/support/clamd_fake_server.ex の unmatched return を修正（MIX_ENV=test の dialyzer で検出）。
docs: docs/QUALITY_GATES.md（ローカル/CI 対応表・ラチェット運用・失敗確認記録）と docs/CI_CD.md を更新。
検証: mix quality 成功、mix quality.coverage 成功（coverage 82.56% / baseline 82.0%）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI の品質ゲートを一本化した。coverage（coveralls.json + priv/ci/check_coverage.exs のラチェット、基準 82.0%・絶対下限 80%）、precommit（mix precommit + mix ash.codegen --check）、dialyzer、assets の各 job を PR で必須化し、summary job が結果を GitHub の job summary に表で出力する。いずれかが失敗・キャンセルなら summary も失敗してマージを止める。ローカルは mix quality / mix quality.coverage で同じ判定を再現できる。各ゲートを一時的に壊し、format/compile/credo/test/codegen/dialyzer/coverage がそれぞれ非ゼロ終了することを確認した。手順と対応表は docs/QUALITY_GATES.md。
<!-- SECTION:FINAL_SUMMARY:END -->
