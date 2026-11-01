---
id: HC-3
title: Incident 昇格/降格・SEV・タイムラインを実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-01T10:18:00Z'
labels:
  - p2
  - incident
milestone: m-2
dependencies: []
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
障害管理フェーズが未着手。チケットから Incident へ昇格し、SEV とタイムラインを管理できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 admin/leader がチケットを Incident に昇格/降格できる
- [x] #2 SEV・影響範囲・周知メモを保持できる
- [x] #3 調査/暫定対応/復旧/監視/振り返りのタイムラインを記録できる
- [x] #4 操作が監査イベントに残る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Incident / IncidentEvent リソースを追加。admin/leader のみ promote/update/demote/timeline 追加が可能。TicketEvent に incident_promoted / incident_demoted / incident_timeline_updated を記録。チケット詳細にインシデントカード、SEV・影響範囲・周知メモ、フェーズ別タイムライン、降格・再昇格を追加。tenant と actor の会社境界を適用。
検証: incident_test 5 passed、incident_live_test 2 passed。mix precommit 239 passed（13 properties / 226 tests）。coveralls 82.1%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
チケットから Incident へ昇格/降格できるようにし、SEV・影響範囲・周知メモを保持した。調査/暫定対応/復旧/監視/振り返りのタイムラインを記録でき、操作は TicketEvent に監査記録を残す。権限は admin/leader に限定し、actor とテナントの会社境界を適用した。検証は incident_test 5件、incident_live_test 2件、mix precommit 239 passed（13 properties / 226 tests）、coveralls 82.1%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
