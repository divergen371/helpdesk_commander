---
id: HC-28
title: P1かつSEV1の全体公開候補と手動承認を実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-03T09:30:00Z'
updated_date: '2026-11-03T09:32:00Z'
labels:
  - incident
  - quality
  - security
milestone: m-2
dependencies: []
priority: medium
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
REQUIREMENTS 5.2.2 の「priority=P1 かつ incident_sev=P1 は全体公開候補とし、管理者/リーダーの手動承認で公開する」が未実装。visibility_scope の値だけ存在し、候補化・承認・却下・監査の経路がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 P1 かつ有効な SEV1 の Incident を持つチケットが global_pending になる
- [x] #2 条件を外れた global_pending は company に戻り、承認済み global は維持される
- [x] #3 管理者/リーダーだけが承認・却下でき、visibility_decided_by_id と visibility_decided_at を記録する
- [x] #4 候補化・承認・却下が TicketEvent の監査イベントに残る
- [x] #5 チケット詳細で公開状態と承認/却下操作を確認できる
- [x] #6 候補化・承認・却下・権限のテストがある
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Helpdesk に公開候補の同期処理を追加し、P1 かつ有効な SEV1 のとき company から global_pending へ、条件を外れたら company へ戻す。2. 管理者/リーダー向けの承認・却下 API を追加し、visibility_decided_by_id / visibility_decided_at を記録する。3. 候補化・取り下げ・承認・却下を TicketEvent に記録する。4. チケット詳細に公開範囲と承認/却下 UI を追加する。5. ドメインと LiveView のテストを追加し、ロードマップの重複した周知メモ項目を整理する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Ticket の visibility_scope を使い、P1 かつ有効な SEV1 Incident のとき global_pending へ自動遷移する同期処理を追加した。SEV 降格・Incident 降格・P1 解除で global_pending は company に戻し、承認済み global は維持する。管理者/リーダーの approve_global_publication / reject_global_publication を追加し、visibility_decided_by_id / visibility_decided_at を記録。候補化・取り下げ・承認・却下を TicketEvent に残す。チケット詳細に公開範囲の表示と承認/却下カードを追加した。周知メモは HC-3 の announcement として実装済みだったため、ロードマップの重複項目を削除した。
検証: global_publication_test 9 passed、global_publication_live_test 3 passed、mix precommit 306 passed（13 properties / 293 tests）、coveralls 83.3%（2681 / 3220 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
P1 かつ有効な SEV1 の Incident を持つチケットを全体公開候補（global_pending）へ自動遷移させ、条件を外れた候補は company に戻すようにした。管理者/リーダーは承認・却下でき、決定者と日時を記録する。候補化・取り下げ・承認・却下は TicketEvent の監査イベントに残し、チケット詳細に公開範囲と操作 UI を追加した。承認済み global は SEV 変更や Incident 降格でも維持する。周知メモは HC-3 の announcement で実装済みと確認し、ロードマップの重複項目を整理した。検証は domain 9件、LiveView 3件、mix precommit 306 passed（13 properties / 293 tests）、coveralls 83.3%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
