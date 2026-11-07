# 添付スキャナのシグネチャ運用 — HC-22

ClamAV の検出力はシグネチャの鮮度に依存する。本手順は更新の自動化・鮮度監視・
更新後の再スキャンの運用手順を定める。

## 0. 実行形態

- clamd サイドカー（推奨、HC-21）: `docs/SANDBOX_SCANNER.md` を参照。サンドボックス化された
  clamd へ `INSTREAM` で検査を委譲し、DB 更新は egress を持つ updater コンテナが担う。
- スキャナコマンド（`ATTACHMENT_SCAN_COMMAND`）: clamscan をアプリ環境で直接実行する形態。

本節以下は共通の運用（コマン ド実行時は `freshclam` をアプリ側で実行する）。

## 1. シグネチャ更新

- `UpdateSignaturesWorker` が毎日 03:15（`config/config.exs` の Cron）に実行される。
- 実行コマンドは `ATTACHMENT_SIGNATURE_UPDATE_COMMAND`（本番既定 `freshclam`）。
  開発・テストでは未設定で何もしない。clamd 構成では `ATTACHMENT_SIGNATURE_UPDATE_COMMAND=""`
  で無効化し、ワーカーは `RELOAD` と `VERSION` の取得だけを行う（DB 更新は updater コンテナ）。
- 更新に成功すると:

  1. `AttachmentSignature`（`attachment_signatures` テーブル）に
     エンジン・版・シグネチャ日時・確認日時を保存
  2. 既存の `clean` / `skipped` 添付を `pending` に戻して再スキャンを enqueue
     （1 回の上限は `ATTACHMENT_RESCAN_LIMIT`、既定 500 件）

- 失敗時は `status = "error"` とエラー内容を保存し、Oban が最大 3 回まで再試行する。
  Oban の失敗は監視（`docs/MONITORING.md` のアラート）で検知する。

### 初回ブートストラップ

本番ではシグネチャ状態が未記録のままアップロードが始まる可能性がある。初回デプロイ後に
一度だけ手動で更新を実行する:

```bash
mix run -e 'HelpdeskCommander.Workers.UpdateSignaturesWorker.perform(%Oban.Job{args: %{}})'
```

## 2. 鮮度監視とアップロード拒否

| 設定 | 既定 | 説明 |
| --- | --- | --- |
| `ATTACHMENT_SIGNATURE_MAX_AGE_HOURS` | 24 | これより古いシグネチャを stale とみなす |
| `ATTACHMENT_SIGNATURE_ENFORCE` | false | true にすると stale / 未記録のときアップロードを拒否 |

- 既定（false）では警告ログのみでアップロードを許可する。
- true にすると `:signature_stale` でアップロードを拒否する。**更新が一度も成功して
  いない状態では全アップロードが拒否される**ため、ブートストラップ後に有効化する。
- 判定基準は `signature_at`（なければ `checked_at`）。

## 3. 更新後の再スキャン

- 再スキャンは `clean` / `skipped` の添付だけを対象とし、`pending` に戻して
  `ScanAttachmentWorker` に積む。既に `pending` のものは対象外なので冪等。
- `failed` は対象外。失敗した添付はチケット詳細から手動再スキャンする（HC-18）。
- 件数上限（既定 500）は `:attachment_rescan_limit` で変更する。大量に溜まった場合は
  ワーカーを複数回実行すると次のバッチが処理される。
- 再スキャン中に enqueue が失敗した添付は `failed`（`scan_note = rescan_enqueue_failed`）
  として隔離し、他の添付の処理を止めない。

## 4. 監視項目

- `update_signatures` ジョブの失敗（Oban の retry/exhausted）
- `attachment_signatures.status = "error"` の残留
- `signature_at` の経過時間（24 時間超）
- `failed` 添付の件数（`scan_status = "failed"`）

## 5. テスト

- `test/helpdesk_commander/attachments/signatures_test.exs` — 記録・鮮度・強制の判定
- `test/helpdesk_commander/workers/update_signatures_worker_test.exs` — 更新成功時の
  メタデータ保存と再スキャン enqueue、失敗時の error 記録と非再スキャン
- `test/helpdesk_commander/helpdesk/attachments_test.exs` — 鮮度ゲートと
  上限付きバッチ再スキャンの冪等性

## 6. 組織固有の YARA ルール（HC-25）

- ルールは `priv/yara/*.yar` としてリポジトリで版管理する。サンプルは
  `priv/yara/internal_rules.yar`。
- 有効化は `ATTACHMENT_YARA_COMMAND`（例: `yara` または絶対パス）。`yara` の場合の
  ルールディレクトリは `ATTACHMENT_YARA_RULES`（既定 `priv/yara`）。カスタムラッパーは
  `{command, args}` 形式で設定する。
- 一致時は `infected` として隔離し、`scan_note` に `YARA: <ルール名>, ...` を記録する。
- YARA の異常終了・タイムアウトは `failed` として隔離する（fail-closed）。

### ルールの追加・更新

1. `priv/yara/` に `.yar` を追加する。ルール名は `Internal_` 接頭辞を付ける。
2. ローカルで構文とマッチを確認する:

   ```bash
   yara -r priv/yara /path/to/sample
   ```

3. PR レビュー後にデプロイする。
4. 既存添付を再スキャンする（上限 500 件ずつ、対象がなくなるまで繰り返す）:

   ```bash
   mix run -e 'IO.inspect(HelpdeskCommander.Helpdesk.Attachments.rescan_outdated())'
   ```

5. 誤検知が出た場合はルールを修正して再デプロイするか、SHA256 許可リスト
   （`/admin/attachment-rules`、HC-24）で該当ファイルを許可する。
