---
id: HC-8
title: 監視サービス連携を実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-03T09:48:00Z'
labels:
  - p2
  - integration
milestone: m-3
dependencies: []
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
監視サービスからのアラートを受けてチケット化する連携がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Webhook でアラートを受信できる
- [x] #2 重複アラートを抑止できる
- [x] #3 チケットまたは Incident を自動生成できる
- [x] #4 受信テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. MonitoringAlert リソースを追加し、source と fingerprint の一意制約でアラートを管理する。2. 汎用 JSON と Alertmanager 形式を正規化し、severity から優先度を決めてチケットを自動起票する。3. 同一 fingerprint の firing は既存チケットが開いている間は抑止し、resolved は会話へ復旧メッセージを残す。4. トークン認証付き Webhook エンドポイントを追加する。5. 会社コード・製品・トークンを環境変数で設定できるようにする。6. 起票・重複抑止・復旧・認証・形式変換のテストと docs を追加する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: MonitoringAlert リソースと Monitoring.Alerts を追加した。汎用 JSON と Alertmanager/Grafana の alerts 配列を正規化し、severity から P1〜P3 を決めて incident チケットを自動起票する。source + fingerprint の一意制約で同一アラートを管理し、対象チケットが closed 以外の間は firing の再送を last_seen_at 更新だけに留める。closed 後の再 firing は新チケットを作ってアラートの ticket_id を差し替える。resolved はアラート状態を更新し、公開会話へ監視復旧メッセージを追加する（チケットは自動クローズしない）。Webhook は X-Monitoring-Token または Bearer で認証し、MONITORING_WEBHOOK_TOKEN / MONITORING_COMPANY_CODE / MONITORING_PRODUCT_ID で設定する。起票先の会社・製品・システムユーザーは自動作成・解決する。
検証: alerts_test 7 passed、monitoring_controller_test 5 passed、mix precommit 328 passed（13 properties / 315 tests）、coveralls 82.6%（2981 / 3609 行）、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
監視サービス Webhook を追加し、汎用 JSON と Alertmanager 形式のアラートから incident チケットを自動起票できるようにした。source と fingerprint で重複を抑止し、対象チケットが閉じるまでは同じ firing を再起票しない。closed 後の再発は新チケットを作り、resolved はアラート状態と公開会話の復旧メッセージに反映する。認証はトークン、起票先は会社コードと製品 ID で設定する。検証は domain 7件、controller 5件、mix precommit 328 passed（13 properties / 315 tests）、coveralls 82.6%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
