---
id: HC-1
title: 関係グラフの表示品質を改善する
status: To Do
assignee: []
created_date: '2026-11-01T08:24:00Z'
labels:
  - p1
  - ui
milestone: m-0
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の /relations は 1 行 10 列のグリッドで、件数が少ないと横一列になり、ノード名とエッジ名の重なりや端の見切れが起きる。テーマごとの凡例色も実際の描画色と一致していない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ノード名とエッジ名が重ならない
- [ ] #2 画面端でノード名が見切れない
- [ ] #3 件数が少ないときも見やすい配置になる
- [ ] #4 凡例の色がライト/ダークの実際のパレットと一致する
- [ ] #5 72vh / min-height 32rem の妥当性を確認する
- [ ] #6 ライト/ダーク両モードの確認手順を docs に残す
<!-- AC:END -->
