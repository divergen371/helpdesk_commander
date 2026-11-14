---
id: HC-42
title: オンプレミス CDR の PoC を実施する
status: To Do
assignee: []
created_date: '2026-11-14T15:38:00Z'
labels:
  - security
  - p3
milestone: m-1
dependencies:
  - HC-27
priority: low
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HC-27 の評価で、CDR（Content Disarm & Reconstruction）は Office / PDF のマクロ・スクリプト・埋め込みオブジェクトを除去でき、検出力の補完になる可能性がある。一方でファイルの忠実性・コスト・運用負荷の確認が必要なため、オンプレミスまたはプライベート環境で PoC を行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 対象形式（docx / xlsx / pptx / pdf）と CDR 候補を比較する
- [ ] #2 ファイルが外部に送信されない構成（オンプレミスまたはプライベート）を確認する
- [ ] #3 変換後の見た目・数式・マクロ除去の忠実性をテストする
- [ ] #4 レイテンシ・コスト・運用負荷を測定する
- [ ] #5 採用可否と次タスクを記録する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
