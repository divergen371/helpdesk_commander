---
id: HC-6
title: 添付ファイル機能を実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-03T09:02:00Z'
labels:
  - p2
  - security
milestone: m-3
dependencies: []
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
チケットやコメントにファイルを添付できない。保存先・容量・形式・安全対策を決めて実装する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 保存先と容量上限が決まっている
- [x] #2 許可する拡張子/MIME を検証する
- [x] #3 ウイルススキャンまたは検査方針が実装されている
- [x] #4 権限のあるユーザーだけが取得できる
- [x] #5 アップロード/取得のテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ローカル保存の Storage を追加し、隔離→検査→公開のディレクトリ構成とキー検証を実装する。2. FilePolicy で拡張子・MIME・10MB・3件を検証する。3. Scanner で ATTACHMENT_SCAN_COMMAND を実行し、clean/infected/failed/skipped を記録して隔離・公開を分岐する。4. TicketAttachment と Attachments コンテキストを追加し、チケット閲覧権限に基づく取得・削除を実装する。5. 詳細画面にアップロード・一覧・削除とダウンロード導線を追加する。6. 保存・検証・スキャン分岐・権限・UI・ダウンロードをテストし、docs を更新する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: TicketAttachment（会社テナント、ファイル名は Cloak 暗号化）と Attachments コンテキストを追加した。実体は priv/uploads に company/ticket/ランダムキーで保存し、quarantine からスキャン結果に応じて clean へ移動する。1ファイル10MB・3件、拡張子とMIMEの両方を検証。Scanner は ATTACHMENT_SCAN_COMMAND の終了コード 0=clean / 1=infected / その他=failed とし、clean と skipped のみダウンロード許可。infected/failed は隔離して403。取得は社内同一会社または外部依頼者本人に限定し、/attachments/:id で配信する。UI にアップロード・一覧・状態表示・削除を追加。docs/DESIGN_ATTACHMENTS.md に保存先・容量・検査・権限を記録した。
検証: attachments_test 6 passed、attachment_live_test 2 passed、attachment_controller_test 5 passed、mix precommit 294 passed（13 properties / 281 tests）、coveralls 83.1%（2622 / 3156 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
添付ファイルをローカル保存で実装した。quarantine に保存してスキャンし、clean/skipped のみ clean ディレクトリへ移してダウンロードを許可、infected/failed は隔離して拒否する。10MB・3件、拡張子とMIMEの両方を検証し、ファイル名は暗号化。取得は同一会社の社内ユーザーまたは外部依頼者本人に限定した。UI にアップロード・状態表示・削除を追加し、スキャナ未設定時は未検査として許可する運用にした（本番は ATTACHMENT_SCAN_COMMAND を設定）。検証は attachments 6件、LiveView 2件、controller 5件、mix precommit 294 passed（13 properties / 281 tests）、coveralls 83.1%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
