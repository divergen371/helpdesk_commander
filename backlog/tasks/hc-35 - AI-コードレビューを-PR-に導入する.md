---
id: HC-35
title: AI コードレビューを PR に導入する
status: Done
assignee: []
created_date: '2026-11-07T10:48:00Z'
updated_date: '2026-11-07T11:55:00Z'
labels:
  - quality
  - ci
  - p2
milestone: m-1
dependencies: []
priority: medium
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
daily-report-void-ts では CodeRabbit 退役に伴い Pullfrog へ切り替えた。このプロジェクトでも PR レビューの自動化を検討する。ただし private リポジトリのコードが外部サービスへ送られるため、PII・機密性の評価と人間の承認なしに導入しない。候補比較 → 決定 → 設定 → 検証 PR の順に進める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pullfrog / CodeRabbit / セルフホスト等の候補を、コード送出し・コスト・権限で比較する
- [x] #2 コードを外部へ送ってよいかの判断を人間が行い、決定と理由を docs に残す
- [x] #3 導入する場合、検証 PR でレビューが実行されることを確認する
- [x] #4 導入しない場合、理由と代替（ローカル静的解析）を記録する
- [x] #5 秘密情報・PII がレビュー対象に含まれない運用を定義する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証完了: コンソールでプロバイダ・モデル設定後、検証 PR #1（https://github.com/divergen371/helpdesk_commander/pull/1）で Pullfrog が実行された。1 回目は mix hex.audit が advisory 検出で exit 1 になり allowlist ゲート前に job が落ちる問題を指摘（妥当）→ hex.audit を情報表示に変更。2 回目は修正を確認し No new issues、加えて CI の mix precommit が format の書き込みモードでゲートが効かない点を指摘（妥当）→ mix format --check-formatted を CI に追加。3 回目は「No new issues found」。全 CI ゲート成功で PR #1 をマージ（710c9ab）。
成果: 実際の不具合 2 件を初回レビューで検出し、修正後にクローズできることを確認。ワークフローはコンソールが main に追加済みのものと同一。docs/QUALITY_AI_REVIEW.md に検証記録を追記。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pullfrog による AI コードレビューを導入し、検証 PR #1 で運用を確認した。初回レビューで dependency audit の exit code 問題と CI format ゲートの穴という実不具合 2 件を検出し、修正後に「No new issues」となるレビューサイクルが機能した。コードは Public リポジトリで外部送信を承認済み、API キーは Secrets のみ。docs/QUALITY_AI_REVIEW.md に比較・導入手順・PII 方針・検証記録を記載した。
<!-- SECTION:FINAL_SUMMARY:END -->
