---
id: HC-23
title: ClamAV の深掘り検査設定と暗号化・アーカイブの扱いを強化する
status: To Do
assignee: []
created_date: '2026-11-03T09:14:00Z'
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
- [ ] #1 ScanArchive / ScanPDF / ScanOLE2 / ScanHTML などの検査対象を明示して設定する
- [ ] #2 MaxScanSize / MaxFileSize / MaxRecursion / MaxFiles を明示し、上限超過を failed として隔離する
- [ ] #3 暗号化 ZIP / Office / PDF は検査不能として隔離または拒否する
- [ ] #4 EICAR 入り ZIP とマクロ付き文書のテストがある
- [ ] #5 設定値と運用上の制約を docs に記載する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
