---
id: HC-37
title: Phoenix セキュリティ静的解析（Sobelow）を CI に追加する
status: Done
assignee: []
created_date: '2026-11-07T10:48:00Z'
updated_date: '2026-11-07T11:18:00Z'
labels:
  - security
  - quality
  - p2
milestone: m-1
dependencies:
  - HC-33
priority: medium
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
credo と dialyzer は一般品質を見るが、Phoenix 固有の XSS・SQL インジェクション・設定漏れ（SECRET_KEY_BASE 等）を狙う静的解析は未導入。Sobelow を CI に入れ、既存の指摘をトリアージして回帰を防ぐ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sobelow を依存に追加し、CI で実行される
- [x] #2 既存の指摘を確認し、修正または理由付きで ignore に分類する
- [x] #3 新規の重大な指摘で CI が失敗する設定になっている
- [x] #4 実行方法とトリアージ方針が docs にある
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: sobelow 0.18 を dev/test に追加。.sobelow-conf（exit: "low"、skip: true）を追加し、CI の precommit job と夜間ジョブで mix sobelow を実行。
トリアージ: Config.CSP は router の put_secure_browser_headers に CSP（default-src self、外部 script/object 禁止、LiveView 用 connect-src ws/wss、inline style 許可）を追加して修正。XSS.ContentType / Traversal.SendFile / Traversal.FileModule（storage・clamd・magic_bytes）/ CI.System（command_runner）は、入力経路を確認して false positive と判断し、関数単位の sobelow_skip と理由コメントを付与。
検証: mix sobelow が 0 findings / exit 0。CSP 追加後も mix test 438 passed。docs/QUALITY_SECURITY.md（方針・初回トリアージ表）と QUALITY_GATES / CI_CD / ROADMAP を更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sobelow による Phoenix セキュリティ静的解析を CI と夜間ジョブに追加した。CSP 未設定の指摘は router の put_secure_browser_headers に CSP を設定して修正し、XSS.ContentType・Traversal（send_file / storage / clamd / magic_bytes）・CI.System は入力経路を確認したうえで関数単位の sobelow_skip と理由コメントで管理する。.sobelow-conf で skip を有効化し、mix sobelow は 0 findings で通過。トリアージ方針と初回対応は docs/QUALITY_SECURITY.md に記録した。
<!-- SECTION:FINAL_SUMMARY:END -->
