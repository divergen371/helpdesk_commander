---
id: HC-16
title: 添付スキャナを本番必須化し、タイムアウトと fail-closed を導入する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-03T09:10:00Z'
updated_date: '2026-11-06T13:56:00Z'
labels:
  - security
  - quality
milestone: m-1
dependencies: []
priority: high
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状は ATTACHMENT_SCAN_COMMAND が未設定だと skipped のままファイルを公開し、System.cmd にもタイムアウトがない。本番で検査漏れを許さず、スキャナ異常時は必ず隔離する必要がある。起動時またはアップロード時に設定を検証し、安全側へ倒す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 本番環境でスキャナ未設定時に起動が失敗する、またはアップロードが拒否される
- [x] #2 skipped を許可しない設定があり、本番の既定で拒否される
- [x] #3 スキャンが既定30秒でタイムアウトし、failed として隔離される
- [x] #4 未設定・タイムアウト・設定不備のテストがある
- [x] #5 docs/DESIGN_ATTACHMENTS.md の運用方針を更新する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Scanner: 未設定時は :attachment_scan_allow_skipped（既定 false）を見て、許可時のみ skipped、非許可時は :scanner_not_configured で fail-closed。設定不備は :invalid_scanner_config。2. タイムアウト: System.cmd を Task.async + Task.yield(timeout) で実行し、既定30秒（ATTACHMENT_SCAN_TIMEOUT_MS）超過で :scan_timeout → failed 隔離。3. runtime.exs: prod で ATTACHMENT_SCAN_COMMAND 未設定なら起動時に raise。allow_skipped は dev/test.exs のみ true（本番は設定しても無視せず、変数自体を本番に置かない）。4. テスト: 未設定+非許可 / タイムアウト / 設定不備 / skipped 許可の既存動作維持を Scanner 単体 + ingest 統合で追加。5. docs/DESIGN_ATTACHMENTS.md 更新。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Scanner を fail-closed 化。未設定時は :attachment_scan_allow_skipped（既定 false）を
見て、許可（dev/test のみ true）以外は {:error, :scanner_not_configured}。設定不備は {:error, :invalid_scanner_config}。
タイムアウト: System.cmd を Task.async + Task.yield(timeout) || Task.shutdown(:brutal_kill) で実行し、
既定 30 秒（ATTACHMENT_SCAN_TIMEOUT_MS）超過で {:error, :scan_timeout}。いずれも ingest 側で
status=failed、quarantine に保持、ダウンロード拒否。
本番必須化: runtime.exs が prod の ATTACHMENT_SCAN_COMMAND 未設定で起動時 raise（AC#1）。
allow_skipped は config/dev.exs と config/test.exs にのみ true を設定し、本番には存在しない（AC#2）。
テスト: Scanner 単体 6 件（skipped 許可 / 未設定 fail-closed / 既定 fail-closed / 設定不備 /
タイムアウト / 不正 timeout 値のフォールバック）+ ingest 統合 3 件（未設定 / タイムアウト /
設定不備 で failed 隔離とダウンロード拒否）を追加（AC#4）。
docs: docs/DESIGN_ATTACHMENTS.md にタイムアウト・fail-closed・本番必須化の運用方針を追記（AC#5）。
検証: mix precommit 357 passed（13 properties / 344 tests）、coveralls 82.1%（3238 / 3942 行）、
dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
添付スキャナを fail-closed 化した。スキャナ未設定は :attachment_scan_allow_skipped（既定 false）が
true の場合のみ :skipped を返し、dev/test 以外は uploads を failed として隔離して公開しない。
本番（config_env :prod）では ATTACHMENT_SCAN_COMMAND 未設定で起動時に失敗する。
スキャン実行は Task.yield による既定 30 秒タイムアウト（ATTACHMENT_SCAN_TIMEOUT_MS で変更可）付きで、
超過・クラッシュ・設定不備・未認可の終了コードはすべて failed として quarantine に保持し、
ダウンロードを拒否する。テストは Scanner 単体 6 件＋ ingest 統合 3 件を追加し、
mix precommit 357 passed（13 properties / 344 tests）、coveralls 82.1%、dialyzer 0 errors。
docs/DESIGN_ATTACHMENTS.md に運用方針を追記済み。
<!-- SECTION:FINAL_SUMMARY:END -->
