---
id: HC-32
title: AI 推論障害時のフォールバックを設計・実装する
status: To Do
assignee: []
created_date: '2026-11-07T10:31:00Z'
labels:
  - p2
  - ai
milestone: m-4
dependencies:
  - HC-13
priority: low
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LiquidAI などの推論を導入した場合、モデル停止・タイムアウト・異常出力で優先度や担当の判定が止まると運用が止まる。ROADMAP のフェーズ 7 にある「モデル障害時のフォールバック（既存のルールベース判定を維持）」をタスク化する。HC-13 の判断後に着手する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 推論が失敗・タイムアウトした場合の挙動（既存ルールへのフォールバック）が定義されている
- [ ] #2 フォールバック発動がログ・メトリクスで検知できる
- [ ] #3 モデル異常出力（範囲外・信頼度不足）の扱いが決まっている
- [ ] #4 障害・フォールバックのテストと運用手順がある
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->
