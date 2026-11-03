# ローカル擬似 Slack での確認手順

実際の Slack アカウントやトンネルなしで、投稿と返信取り込みを確認する。

## 1. 擬似 Slack を起動

```bash
mix run --no-halt dev/local_slack_server.exs
```

- メッセージ一覧: http://127.0.0.1:4010/
- API: `http://127.0.0.1:4010/api/chat.postMessage`

## 2. アプリを Slack 設定付きで起動

別ターミナルで:

```bash
SLACK_BOT_TOKEN=local-token \
SLACK_SIGNING_SECRET=local-secret \
SLACK_CHAT_CHANNEL_ID=C-LOCAL \
SLACK_API_BASE=http://127.0.0.1:4010/api \
mix phx.server
```

## 3. 投稿を確認

1. http://127.0.0.1:4000 にログインする。
2. チケット詳細で「公開コメント追加」からメッセージを投稿する。
3. http://127.0.0.1:4010/ に投稿が表示されることを確認する。
4. 一覧の `ts` を控える。

## 4. Slack 返信を取り込む

控えた `ts` を `thread_ts` として返信を送る。

```bash
SLACK_SIGNING_SECRET=local-secret \
  mix run dev/send_slack_reply.exs <thread_ts> "Slack からの返信"
```

チケット詳細の公開コメントに、`Slack Bridge` 投稿者で返信が追加される。
同じコマンドを再実行しても、同じ `ts` でなければ増えるため、
重複確認は同じイベントを再送するテストで行う。

## 確認ポイント

- 投稿が Slack 側に1回だけ出る
- 返信が公開会話に1回だけ入る
- 内部メモは Slack に出ない
- 署名が不正な返信は 401 になる
- Bot 投稿やスレッド外の投稿は無視される
