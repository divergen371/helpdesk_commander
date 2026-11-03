# 監視サービス連携（HC-8）

## 概要

監視サービスから Webhook でアラートを受け取り、チケットを自動起票する。

- 汎用 JSON と Alertmanager / Grafana 形式の `alerts` 配列を受け付ける。
- `source` と `fingerprint` で同一アラートを識別する。
- 同じ fingerprint の firing は、対象チケットが閉じられるまで重複起票しない。
- `resolved` はアラート状態を更新し、公開会話へ復旧メッセージを残す。
- チケットの状態は自動で閉じない（人の判断を残す）。

## エンドポイント

```text
POST /integrations/monitoring/alerts
X-Monitoring-Token: <token>
Content-Type: application/json
```

`Authorization: Bearer <token>` でもよい。

## 環境変数

| 変数 | 用途 |
| --- | --- |
| `MONITORING_WEBHOOK_TOKEN` | 必須。未設定だと 503 |
| `MONITORING_COMPANY_CODE` | 起票先の会社コード。既定は `A-000001` |
| `MONITORING_PRODUCT_ID` | 起票先の製品 ID。未設定なら有効な先頭製品 |

製品が1件もない場合は 503 になる。

## 汎用ペイロード

```json
{
  "source": "prometheus",
  "fingerprint": "cpu-high-db1",
  "status": "firing",
  "severity": "critical",
  "title": "CPU usage high",
  "description": "CPU is above 95%",
  "labels": {"service": "api", "instance": "db1"}
}
```

## Alertmanager 形式

```json
{
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "fingerprint": "diskfull-db1",
      "labels": {"alertname": "DiskFull", "severity": "warning"},
      "annotations": {"summary": "Disk is almost full"}
    }
  ]
}
```

## 変換ルール

| 入力 | チケット |
| --- | --- |
| `critical` / `page` | P1 |
| `error` / `high` | P2 |
| `warning` / `warn` | P2 |
| `info` / `low` | P3 |

- 件名: `[Alert] <title>`
- 種別: `incident`
- 状態: `new`
- 依頼者: 会社ごとの `Monitoring` システムユーザー
- 監査: `TicketEvent` に `monitoring_alert_received` を記録

fingerprint がない場合は、`source`・`title`・ソート済み labels から SHA256 で生成する。

## 重複抑止

- 同じ `source` + `fingerprint` のアラートは `monitoring_alerts` に1行だけ持つ。
- 対象チケットが `closed` 以外なら、firing の再送は `last_seen_at` の更新だけ行う。
- 対象チケットが `closed` なら、新しいチケットを作り、アラートの `ticket_id` を差し替える。
- `resolved` はアラートを `resolved` にし、チケットの公開会話へ復旧メッセージを追加する。

## 制約

- 1つの Webhook 設定につき1会社・1製品を対象にする。
- 監視アラートから Incident リソースへの自動昇格はしない（チケットの種別を incident にするだけ）。
- アラート解除でチケットを自動クローズしない。
- fingerprint の安定性は監視サービスの設定に依存する。ラベルが毎回変わると重複抑止できない。
