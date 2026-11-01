---
id: HC-7
title: 会話チャット連携（Slack など）を実装する
status: To Do
assignee: []
created_date: '2026-11-01T08:24:00Z'
labels:
  - p2
  - integration
milestone: m-3
dependencies: []
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
通知の Slack Webhook は実装済みだが、会話そのものをチャットと同期する連携は未着手。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 対象チケットの会話を Slack チャンネルへ投稿できる
- [ ] #2 チャットからの返信を会話ログに取り込める
- [ ] #3 重複投稿を防ぐ
- [ ] #4 連携先の認証情報を環境変数で管理する
<!-- AC:END -->
