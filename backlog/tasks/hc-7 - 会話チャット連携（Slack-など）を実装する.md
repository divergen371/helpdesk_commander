---
id: HC-7
title: 会話チャット連携（Slack など）を実装する
status: Done
assignee:
  - '@codex'
created_date: '2026-11-01T08:24:00Z'
updated_date: '2026-11-03T09:44:00Z'
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
- [x] #1 対象チケットの会話を Slack チャンネルへ投稿できる
- [x] #2 チャットからの返信を会話ログに取り込める
- [x] #3 重複投稿を防ぐ
- [x] #4 連携先の認証情報を環境変数で管理する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Slack 設定（Bot Token / Signing Secret / Channel）を環境変数から読み、署名検証と chat.postMessage 投稿を実装する。2. チケットと Slack スレッド、会話メッセージと外部メッセージの対応を保存するリソースを追加する。3. 公開メッセージ投稿時に Oban で Slack へ送信し、再実行時は既存リンクで重複を防ぐ。4. Slack Events API の受信エンドポイントを追加し、スレッド返信を公開会話へ取り込む。5. チケット詳細からの投稿、受信、重複、署名検証をテストする。6. 運用手順と環境変数を docs に記載する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: Slack の公開メッセージ投稿とスレッド返信取り込みを追加した。SLACK_BOT_TOKEN / SLACK_SIGNING_SECRET / SLACK_CHAT_CHANNEL_ID / SLACK_API_BASE を環境変数から読み、chat.postMessage でチケットごとのスレッドへ投稿する。chat_threads にチャンネルと thread_ts、chat_message_links に外部メッセージ ID を保存し、再実行・Slack 再送は一意制約と既存リンクで重複を防ぐ。公開メッセージ投稿時のみ Oban の integrations キューへ積む。Events API は RawBodyReader で生ボディを保持し、X-Slack-Signature とタイムスタンプを検証する。スレッド返信は公開会話へ取り込み、投稿者は会社ごとの Slack Bridge システムユーザー、Slack ユーザー ID は meta に保存する。Bot 投稿・subtype 付き・スレッド外は無視する。
検証: slack_test 5 passed、slack_controller_test 4 passed、chat_slack_live_test 1 passed、mix precommit 316 passed（13 properties / 303 tests）、coveralls 82.8%（2809 / 3394 行）、dialyzer 0 errors、ash.codegen --check 成功。

ローカル確認用に dev/local_slack_server.exs（chat.postMessage とメッセージ一覧）と dev/send_slack_reply.exs（署名付きイベント送信）を追加し、docs/LOCAL_SLACK_TEST.md に手順を記載した。実際に擬似 Slack を起動し、公開メッセージの投稿（outbound リンク）とスレッド返信の取り込み（inbound リンク、body=Slackからの返信です、meta に slack_user_id）まで確認した。なお runtime.exs の Slack 設定が prod 限定だったため、dev/test でも環境変数を読む位置へ修正した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Slack とチケット公開会話の双方向連携を実装した。公開メッセージはチケットごとの Slack スレッドへ Oban 経由で投稿し、Slack スレッドの返信は署名検証済みの Events API から公開会話へ取り込む。chat_threads と chat_message_links でスレッド・外部メッセージを対応付け、再実行や Slack 再送による重複投稿を防ぐ。認証情報は環境変数で管理し、Bot 投稿・スレッド外・内部メモは同期しない。検証は Slack 5件、controller 4件、LiveView 1件、mix precommit 316 passed（13 properties / 303 tests）、coveralls 82.8%、dialyzer 0 errors、ash.codegen --check 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
