---
id: HC-1
title: 関係グラフの表示品質を改善する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-01T08:42:00Z'
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
- [x] #1 ノード名とエッジ名が重ならない
- [x] #2 画面端でノード名が見切れない
- [x] #3 件数が少ないときも見やすい配置になる
- [x] #4 凡例の色がライト/ダークの実際のパレットと一致する
- [x] #5 72vh / min-height 32rem の妥当性を確認する
- [x] #6 ライト/ダーク両モードの確認手順を docs に残す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現状の Sigma.js 設定とテーマパレットを確認する
2. グリッド配置を件数に応じて調整し、少件数時の横一列を避ける
3. ラベルの重なりを減らす設定と余白を調整する
4. 凡例を実際の描画パレットと一致させる
5. ライト/ダーク両モードで表示を確認し、手順を docs に残す
6. mix precommit / coveralls / dialyzer で検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 件数に応じた正方形グリッド（1件は中央）、短いエッジ名（再起票/重複/依存/関連）、エッジ名は8本以下でのみ表示、labelDensity/labelGridCellSize/StagePadding 120、高さ clamp(32rem, 72vh, 64rem)。
テーマ色は assets/css/app.css の --graph-* を正本にし、Sigma と凡例が同じ変数を参照。
検証: relation_graph_live_test 5 passed（3件で2行配置、1件で中央、エッジ名が「依存」）。mix precommit 227 passed / 13 properties 214 tests。coveralls 82.6%。dialyzer 0 errors。
DOM確認: 3ノードが (-3.5,-3.5),(3.5,-3.5),(-3.5,3.5)、表示高さ512px、ライト/ダークでCSS変数と凡例色が一致、canvas 2448非ゼロピクセル。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
関係グラフの配置・ラベル・凡例・余白を調整した。件数に応じた正方形グリッドで少件数でも横一列にならず、1件は中央に配置する。エッジ名は短い日本語表記にし、8本以下でのみ表示して重なりを避ける。テーマ色はCSS変数を正本にしてSigmaと凡例で共有し、ライト/ダークの描画色と凡例が一致する。高さは clamp(32rem, 72vh, 64rem) に調整した。検証は relation_graph_live_test 5件、mix precommit 227 passed（13 properties / 214 tests）、coveralls 82.6%、dialyzer 0 errors。確認手順を docs/DESIGN_TICKET_RELATIONS.md に追記した。
<!-- SECTION:FINAL_SUMMARY:END -->
