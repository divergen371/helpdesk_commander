---
id: HC-40
title: 夜間CIのPostgreSQL接続ポートを修正する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-09T07:34:00Z'
updated_date: '2026-11-09T08:12:00Z'
labels: []
dependencies: []
references:
  - https://github.com/divergen371/helpdesk_commander/actions/runs/42470078398
  - https://github.com/divergen371/helpdesk_commander/actions/runs/42581998242
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
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
通常CIと同じPOSTGRES_PORT: 5432を夜間CIのworkflow envに追加する。YAML構文、サービス公開ポートとの一致、変更範囲を確認する。Elixir・PostgreSQLがないため実行検証の可否を明記する。コミット・pushは行わない。

夜間workflowのenvへPOSTGRES_PORT: 5432を追加済み。PyYAMLで構文と通常CI・DB公開ポートの一致を検証し成功。config/test.exsの差分なし、既定5433の維持を確認。git diff --check成功。mix precommitはmix未導入で実行不可。GitHub未反映のため夜間CI実行確認は未完了。タスクはIn Progressのまま保持。

ユーザーからコミット・push・夜間CI検証の許可を取得。修正をc1283200cccd0456a3a690f9b5fb998c612e67f1でfix/nightly-postgres-portへ反映、PR #4を作成。通常CI #92成功。Nightly #2 (42581998242) を修正ブランチで手動開始した。

Nightly #2 が全工程success。451 passed (13 properties, 438 tests)、coverage 82.59%、Dialyzer Total errors: 0。変異スコアは認可43 killed/4 ignored、添付81 killed、PII18 killed/3 ignored、会社コード34 killed/3 ignored、すべて100%でsurvived 0。Elixir・npm依存監査も成功。mix precommitそのものはローカル未導入で未実行だが夜間CIで個別品質ゲートを完走。結果をPR説明と本タスクへ記録。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
夜間CIにPOSTGRES_PORT: 5432を明示し、ローカル既定5433は維持。修正コミットc128320でNightly #2が全工程成功し、DB接続失敗の解消を実証。PR #4は未マージ。
<!-- SECTION:FINAL_SUMMARY:END -->
