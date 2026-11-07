---
id: HC-23
title: ClamAV の深掘り検査設定と暗号化・アーカイブの扱いを強化する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-03T09:14:00Z'
updated_date: '2026-11-06T14:21:00Z'
labels:
  - security
  - quality
milestone: m-1
dependencies:
  - HC-16
priority: high
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の ClamAV は既定設定のまま実行され、アーカイブの深さ・サイズ上限・暗号化ファイル・Office マクロの扱いが明示されていない。検査範囲を広げ、検査不能なファイルを黙って通さないようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ScanArchive / ScanPDF / ScanOLE2 / ScanHTML などの検査対象を明示して設定する
- [x] #2 MaxScanSize / MaxFileSize / MaxRecursion / MaxFiles を明示し、上限超過を failed として隔離する
- [x] #3 暗号化 ZIP / Office / PDF は検査不能として隔離または拒否する
- [x] #4 EICAR 入り ZIP とマクロ付き文書のテストがある
- [x] #5 設定値と運用上の制約を docs に記載する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Attachments.Clamav モジュールを新設: 検査対象フラグ（scan-archive/pdf/ole2/html）、上限フラグ（max-scansize/filesize/recursion/files、既定は ClamAV の既定値 100M/25M/16/10000）、alert-encrypted/alert-macros を args() で明示生成。scan_command/1 でコマンドが clamscan のときだけ深掘り引数を付ける（runtime.exs から呼び出し）。2. 暗号化アーカイブ・Office マクロは alert 化で exit 1（infected）→ 隔離。上限超過・クラシャは exit 2 → failed 隔離（既存 Scanner のマッピングを再利用）。3. テスト: args の既定/上書き、scan_command の分岐、EICAR 入り ZIP / マクロ文書 / 暗号化 ZIP / 上限超過をスタブスキャナで ingest し隔離ことを確認。4. docs/DESIGN_ATTACHMENTS.md に設定値と運用上の制約を記載。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Attachments.Clamav を新設。clamscan 指定時に args() が検査対象（--scan-archive/pdf/ole2/html）、
上限（--max-scansize=100M / --max-filesize=25M / --max-recursion=16 / --max-files=10000）、
検査不能の可視化（--alert-encrypted / --alert-macros）を明示。上限は config
:attachment_scan_clamav で上書き可。scan_command/1 は basename が clamscan のときだけ
引数を付与し、runtime.exs から呼び出す（clamdscan 等のラッパーは対象外）。
暗号化 ZIP / Office / PDF とマクロ文書は exit 1（infected）→ 隔離。上限超過・スキャナ異常は
exit 2 → failed 隔離（HC-16 のマッピングを再利用）。AC#1〜#3 を満たす。
テスト: Clamav 3 件（既定 args / 上書き / clamscan 判定）。
ingest 統合 4 件: EICAR 入り ZIP（unzip スタブ）、マクロ付き docx、暗号化 ZIP、上限超過
→ それぞれ infected / failed で quarantine 保持・ダウンロード拒否（AC#4）。
docs: DESIGN_ATTACHMENTS.md にフラグ表・上書き方法・clamscan 以外は自動付与しない旨・
ClamAV 0.100 以降前提を追記（AC#5）。
検証: mix precommit 375 passed（13 properties / 362 tests）、coveralls 82.2%（3269 / 3976 行）、
dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ClamAV の深掘り検査設定を明示化した。ATTACHMENT_SCAN_COMMAND が clamscan のとき、
検査対象（archive/pdf/ole2/html）、上限（max-scansize 100M・max-filesize 25M・
max-recursion 16・max-files 10000）、検査不能の可視化（alert-encrypted・alert-macros）を
自動付与する。上限は config :attachment_scan_clamav で上書きでき、clamscan 以外の
ラッパーには自動付与しない。暗号化アーカイブ・マクロ文書は infected として、上限超過や
スキャナ異常は failed として quarantine に保持しダウンロードを拒否する。
テストは Clamav 単体 3 件と EICAR 入り ZIP・マクロ付き docx・暗号化 ZIP・上限超過の
ingest 統合 4 件を追加。mix precommit 375 passed（13 properties / 362 tests）、
coveralls 82.2%、dialyzer 0 errors。docs/DESIGN_ATTACHMENTS.md に設定値と制約を追記。
<!-- SECTION:FINAL_SUMMARY:END -->
