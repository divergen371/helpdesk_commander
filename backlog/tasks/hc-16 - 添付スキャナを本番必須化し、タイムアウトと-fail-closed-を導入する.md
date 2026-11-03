---
id: HC-16
title: 添付スキャナを本番必須化し、タイムアウトと fail-closed を導入する
status: To Do
assignee: []
created_date: '2026-11-03T09:10:00Z'
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
- [ ] #1 本番環境でスキャナ未設定時に起動が失敗する、またはアップロードが拒否される
- [ ] #2 skipped を許可しない設定があり、本番の既定で拒否される
- [ ] #3 スキャンが既定30秒でタイムアウトし、failed として隔離される
- [ ] #4 未設定・タイムアウト・設定不備のテストがある
- [ ] #5 docs/DESIGN_ATTACHMENTS.md の運用方針を更新する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
