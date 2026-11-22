# 定期レポート配信の運用手順（HC-29）

ダッシュボードの分析（HC-5）で集計した運用統計を、日次・週次で自動配信する仕組み。

## 1. 基本方針

- 配信は Oban の Cron（毎日 08:00 UTC）から `DispatchScheduledReportsWorker` が起動し、
  本日配信対象のスケジュールごとに `DeliverScheduledReportWorker` をキューに入れる。
- 日次スケジュールは毎日、週次スケジュールは月曜日（UTC）に配信する。
- レポートの内容は `Helpdesk.Analytics.summarize/2`（直近 30 日）に基づき、
  サマリ・ステータス別・優先度別・担当者別の集計を含む。
- 送信先は会社単位の設定で、他社のスケジュール・宛先には配信されない。

## 2. 設定方法（管理画面）

`/admin/report-schedules`（管理者のみ）で次を設定する。

| 項目 | 説明 |
| --- | --- |
| 名前 | スケジュールの識別名 |
| 周期 | 日次 / 週次（月曜） |
| 配信先 | メール（PDF 添付）/ チャット Webhook |
| 宛先 | メールの場合はカンマ区切りのメールアドレス。チャットの場合は未使用 |
| 有効/無効 | 一時停止は「無効にする」で切替（外部送信を停止） |

「今すぐ送信」で即時配信ジョブ（`reports` キュー）を登録できる。

## 3. チャネルの前提設定

- **メール**: `NOTIFICATION_EMAIL_ENABLED=true` と送信元 `NOTIFICATION_FROM_EMAIL`、
  さらに Swoosh のメール アダプタ（`config :helpdesk_commander, HelpdeskCommander.Mailer,
  adapter: ...`、既定は開発用の `Swoosh.Adapters.Local`）を SMTP 用へ設定する必要がある。
  アダプタ未設定のまま有効化すると送信は行われない。
  PDF を `application/pdf` 添付で送信する。
- **チャット**: `SLACK_WEBHOOK_URL`（Slack 互換 Inbound Webhook）を設定すると有効になる
  （`NOTIFICATIONS_CHAT_ENABLED` という変数は存在しない）。
  本文はテキストのみ（PDF は添付できない）。
- いずれも未設定の場合は配信に失敗し、`last_error` に `email_not_configured` /
  `chat_not_configured` が記録される。

## 4. 失敗時の再試行と検知

- 配信ジョブは最大 5 回、15 秒から指数バックオフ（最大 5 分）で再試行する。
- 同一期間（日次: 同一 UTC 日、週次: 同一周）にすでに送信済みのスケジュールは
  再送しない（`mark_sent` 失敗後の再試行で重複送信されるのを防ぐ）。
  「今すぐ送信」はこのチェックを省略して強制配信する。
- 再試行でも失敗した場合、スケジュールの `last_failed_at` / `last_error` に残り、
  管理画面の該当行に「最終エラー」として表示される。
- すべての失敗は `Logger` に `[reports.deliver_scheduled_report]` プレフィックスで
  記録される。監視連携（HC-8）の Webhook 通知や夜間メトリクス（HC-36）で検知できる。
- 宛先が空のメール スケジュールは `no_recipients` で失敗する（全社配信にはしない）。

## 5. 監査と個人情報

- レポートに含まれるのは集計値のみで、チケット本文やユーザーのメールアドレスは
  含まれない（担当者別は `display_name`）。
- **PDF は ASCII のみ**（base-14 Helvetica の制約）。日本語の `display_name` は
  `user-<id>` に置き換えられ、節見出しは英語（Summary / By status など）になる。
  日本語の詳細はメール本文・チャット本文（UTF-8）で確認できる。
- 配信成功・失敗の記録は `report_schedules` テーブルに保持する。
