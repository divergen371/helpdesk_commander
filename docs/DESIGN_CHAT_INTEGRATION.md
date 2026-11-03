# Slack チャット連携（HC-7）

## 概要

チケットの公開会話と Slack を双方向に同期する。

- 公開メッセージを投稿すると、チケットごとの Slack スレッドへ送る。
- Slack スレッドの返信を、チケットの公開会話へ取り込む。
- 内部メモ（`internal_private`）は Slack へ送らない。
- 自動リンクや自動返信は行わない。

## 必要な環境変数

| 変数 | 用途 |
| --- | --- |
| `SLACK_BOT_TOKEN` | `chat.postMessage` を呼ぶ Bot Token |
| `SLACK_SIGNING_SECRET` | Events API の署名検証 |
| `SLACK_CHAT_CHANNEL_ID` | 投稿先チャンネル ID |
| `SLACK_API_BASE` | テスト・プロキシ用。既定は `https://slack.com/api` |

`SLACK_BOT_TOKEN` と `SLACK_CHAT_CHANNEL_ID` が揃ったときだけ投稿が有効になる。
署名検証は `SLACK_SIGNING_SECRET` が必要。

## Slack アプリ設定

1. Bot Token Scopes に `chat:write` を追加する。
2. Event Subscriptions を有効にし、Request URL を
   `https://<host>/integrations/slack/events` にする。
3. Subscribe to bot events に `message.channels`（または対象チャンネルに応じたイベント）を追加する。
4. 投稿先チャンネルへ Bot を招待する。

## 動作

### 送信

- チケット詳細で公開メッセージを投稿すると、`PublishChatMessageWorker` が
  `integrations` キューへ積まれる。
- チケットごとに最初の投稿で Slack スレッドを作り、`chat_threads` に保存する。
- 2 通目以降は同じ `thread_ts` へ返信する。
- メッセージと Slack の `ts` の対応を `chat_message_links` に保存する。
- 同じメッセージに対する再実行は既存リンクを確認して送らない。

### 受信

- Slack Events API の `message` イベントのうち、`thread_ts` があるものだけを取り込む。
- `bot_id` や `subtype` 付きのイベントは無視する。
- チャンネルと `thread_ts` から `chat_threads` を引き、対象チケットを特定する。
- 外部メッセージ ID（Slack の `ts`）で重複を排除する。
- 投稿者は会社ごとの `Slack Bridge` システムユーザーにする。
- 元の Slack ユーザー ID は `conversation_messages.meta` に保存する。

## セキュリティ

- Events API は `X-Slack-Signature` と `X-Slack-Request-Timestamp` を検証する。
- タイムスタンプが 5 分以上ずれたリクエストは拒否する。
- 署名検証にはパース前の生ボディを使う（`RawBodyReader`）。
- Slack からのメッセージを再び Slack へ送らない（ループ防止）。

## 制約

- スレッド返信のみ取り込む。チャンネルへの新規投稿は取り込まない。
- Slack ユーザーとアプリユーザーの名寄せはしない。
- 添付ファイルの同期は未対応。
- Bot Token が無効・チャンネル未招待の場合は投稿ジョブが失敗し、Oban が再試行する。
