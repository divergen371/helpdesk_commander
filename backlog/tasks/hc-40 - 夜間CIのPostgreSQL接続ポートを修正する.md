---
id: HC-40
title: 夜間CIのPostgreSQL接続ポートを修正する
status: In Progress
assignee:
  - '@codex'
created_date: '2026-11-09T07:34:00Z'
updated_date: '2026-11-09T07:34:00Z'
labels: []
dependencies: []
references:
  - https://github.com/divergen371/helpdesk_commander/actions/runs/42470078398
type: bug
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-08の夜間CIはDBサービスを5432で公開する一方、POSTGRES_PORT未指定によりlocalhost:5433へ接続して停止した。通常CIには5432の明示指定がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 夜間CIのテスト接続ポートがPostgreSQLサービスのホスト側ポートと一致する
- [x] #2 ローカルテスト用の既定ポート5433を変更しない
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
通常CIと同じPOSTGRES_PORT: 5432を夜間CIのworkflow envに追加する。YAML構文、サービス公開ポートとの一致、変更範囲を確認する。Elixir・PostgreSQLがないため実行検証の可否を明記する。コミット・pushは行わない。

夜間workflowのenvへPOSTGRES_PORT: 5432を追加済み。PyYAMLで構文と通常CI・DB公開ポートの一致を検証し成功。config/test.exsの差分なし、既定5433の維持を確認。git diff --check成功。mix precommitはmix未導入で実行不可。GitHub未反映のため夜間CI実行確認は未完了。タスクはIn Progressのまま保持。
<!-- SECTION:NOTES:END -->
