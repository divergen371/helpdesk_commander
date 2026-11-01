---
id: HC-2
title: Ash multitenancy で company 境界を強制する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-01T10:00:00Z'
labels:
  - p2
  - security
milestone: m-1
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
company 境界は現在 Domain クエリのフィルタで維持している。API 化や新規画面の追加時に漏れが起きやすいため、Ash の multitenancy で強制する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 company_id を tenant として Ash の multitenancy を設定する
- [x] #2 既存の会社スコープ付きクエリが tenant 前提で動作する
- [x] #3 越境アクセスが拒否されるテストがある
- [x] #4 既存テストとカバレッジ基準を維持する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 共通の TenantScope（read の会社フィルタ）と TenantGuard（write の会社一致検証）を追加する
2. company_id を持つ主要リソースに multitenancy（attribute / global? true）を設定する
3. Domain の会社スコープ付き読み取りに tenant を渡す
4. 越境読み取り・越境書き込みの拒否テストを追加する
5. mix precommit / coveralls / dialyzer で検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: company_id を attribute tenant とする multitenancy を主要13リソースに設定（global? true）。Tenancy.Scope が tenant または actor の company_id で read を絞り、Tenancy.Guard が越境 create/update/destroy を拒否。Domain の会社スコープ付き読み取りに tenant を渡し、Web フォームにも actor を渡した。tenant 化に伴う unique index/FK 更新の migration と、task_events/ticket_task_links/ticket_notifications/ticket_verifications の CASCADE/NILIFY を復元する migration を追加。
検証: tenancy_test 5 passed（tenant read、actor read、domain read、越境 create/update 拒否）。mix precommit 232 passed / 13 properties 219 tests。coveralls 82.7%。dialyzer 0 errors。ash.codegen --check exit 0。実機で / /tickets /tasks /products /relations /notifications /tickets/:id を表示確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
company_id を Ash の attribute tenant として主要リソースに設定し、Tenancy.Scope で read、Tenancy.Guard で write の会社境界を強制した。Domain の会社スコープ付きクエリは tenant を渡し、画面のフォームも actor を渡す。tenant 化に伴う index/FK の migration と、既存の CASCADE/NILIFY を復元する migration を追加した。検証は tenancy_test 5件、mix precommit 232 passed（13 properties / 219 tests）、coveralls 82.7%、dialyzer 0 errors、ash.codegen --check 成功。実機で主要画面を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
