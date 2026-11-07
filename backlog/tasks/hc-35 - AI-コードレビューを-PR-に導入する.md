---
id: HC-35
title: AI コードレビューを PR に導入する
status: In Progress
assignee: []
created_date: '2026-11-07T10:48:00Z'
updated_date: '2026-11-07T11:32:00Z'
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
- [ ] #1 Pullfrog / CodeRabbit / セルフホスト等の候補を、コード送出し・コスト・権限で比較する
- [ ] #2 コードを外部へ送ってよいかの判断を人間が行い、決定と理由を docs に残す
- [ ] #3 導入する場合、検証 PR でレビューが実行されることを確認する
- [ ] #4 導入しない場合、理由と代替（ローカル静的解析）を記録する
- [ ] #5 秘密情報・PII がレビュー対象に含まれない運用を定義する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 テストが通る
- [ ] #2 ドキュメントを更新する
- [ ] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
候補比較と方針決定: Pullfrog（GitHub Actions + BYOK、レビュー枠なし、AGENTS.md を基準）を採用。CodeRabbit（枠不足）、Copilot code review、セルフホスト型と比較。ユーザー判断によりリポジトリが Public であることを確認し、外部送信を承認済み。
実装: .github/workflows/pullfrog.yml（公式ワークフロー、Secrets 参照のみでキーはコミットしない）、docs/QUALITY_AI_REVIEW.md（比較・導入手順・秘密情報/PII の扱い・検証状況）。
残り: (1) Pullfrog コンソールでリポジトリ接続と購読/BYOK 設定、(2) GitHub Secrets にプロバイダの API キー登録、(3) 検証 PR でレビュー実行を確認。これらはリポジトリ管理者の操作が必要なため、AC#3 は未完了のまま。
<!-- SECTION:NOTES:END -->
