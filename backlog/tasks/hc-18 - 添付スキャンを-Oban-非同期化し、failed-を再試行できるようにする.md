---
id: HC-18
title: 添付スキャンを Oban 非同期化し、failed を再試行できるようにする
status: Done
assignee: []
created_date: '2026-11-03T09:10:00Z'
updated_date: '2026-11-06T14:28:00Z'
labels:
  - security
  - quality
  - ops
milestone: m-1
dependencies:
  - HC-16
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スキャンをアップロード処理内で同期実行しているため、大きなファイルやスキャナのハングで LiveView が待たされる。Oban の非同期ジョブへ移し、失敗時の再試行と手動再スキャンを可能にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 アップロードは pending を返し、スキャンは Oban ジョブで実行される
- [x] #2 failed は上限付きの指数バックオフで再試行される
- [x] #3 管理者またはアップロード者が手動で再スキャンできる
- [x] #4 同じ添付が二重にスキャンされない冪等性がある
- [x] #5 非同期実行・再試行・二重実行防止のテストがある
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ScanAttachmentWorker（queue :attachments, max_attempts 5, unique: available/scheduled/executing/retryable, period infinity）を新設。ingest は pending の添付を作成して即 return し、ジョブを enqueue。perform は clean/infected を no-op（冪等）、pending/failed を再スキャン。Attachments.scan_attachment/1 を公開してテスト・手動運用から同期的に実行可能にした。
バックオフ: backoff/1 で attempt に応じ 30s→60s→…、上限 300s（テストで 1/2/4/5/9 を検証）。
手動再スキャン: Attachments.rescan/2 + can_rescan?/2（failed のみ、管理者・リーダーまたはアップロード者）。ステータスを pending に戻して再 enqueue。チケット詳細に「再スキャン」ボタンと phx-click ハンドラ、フラッシュ表示。
二重実行防止: Oban unique と terminal status の no-op で担保。アップロード時のフラッシュも「件を追加しました（検査を開始しました）」に変更。
テスト: worker 6 件（clean 化 / failed で {:error, :scan_failed} / terminal no-op / 削除済み / unique 1 件 / backoff cap）、attachments に手動再スキャン 3 件、LiveView に再スキャンボタン 1 件 + 非同期 enqueue 検証。既存の添付テスト/コントローラテストは scan_attachment を明示実行する形へ更新。
検証: mix precommit 392 passed（13 properties / 379 tests）、coveralls 82.5%（3338 / 4047 行）、dialyzer 0 errors、ash.codegen --check 成功。docs/DESIGN_ATTACHMENTS.md・STATUS・README 更新済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
添付スキャンを Oban（queue :attachments）で非同期化した。アップロードは pending を返し、ScanAttachmentWorker が実体を検査する。失敗は上限付き指数バックオフ（30 秒から倍々、最大 5 分・5 回）で再試行し、5 回失敗で failed 隔離。unique 制約と clean/infected の no-op で二重実行を防ぎ、冪等性を確保。failed は管理者・リーダーまたはアップロード者がチケット詳細から手動再スキャンでき、pending に戻してジョブを積み直す。テストは worker 6 件・手動再スキャン 3 件・LiveView 2 件を追加し、mix precommit 392 passed（13 properties / 379 tests）、coveralls 82.5%、dialyzer 0 errors。
<!-- SECTION:FINAL_SUMMARY:END -->
