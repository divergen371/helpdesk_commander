# 添付ファイル設計（HC-6）

## 保存先
- ローカルディスクに保存する。既定は `priv/uploads/`（`ATTACHMENTS_ROOT` で変更可能）。
- 保存キーは `company_id/ticket_id/<ランダム32桁>`。ユーザー入力のファイル名はパスに使わない。
- アップロード直後は `quarantine/` に置く。スキャン結果が `clean` または `skipped` の
  ときだけ `clean/` へ移動する。
- 実体は静的配信せず、`/attachments/:id` のコントローラ経由でのみ返す。
- ファイル名は PII を含み得るため Cloak で暗号化して保存する。

## 容量・形式
- 1ファイル 10MB、1回 3件まで。
- 拡張子と MIME の両方を検証する。許可する組み合わせは
  `HelpdeskCommander.Attachments.FilePolicy` を正本とする。
  - 画像: png / jpg / jpeg / gif / webp
  - 文書: pdf / txt / csv / docx / xlsx / pptx
  - 圧縮: zip
- 拡張子だけ・MIME だけでは通さない。

## ウイルス検査と隔離
- `ATTACHMENT_SCAN_COMMAND` に `clamscan` などを設定すると、保存したファイルを検査する。
  - 終了コード 0: `clean` → `clean/` へ移動してダウンロード可
  - 終了コード 1: `infected` → `quarantine/` に残しダウンロード拒否
  - それ以外: `failed` → `quarantine/` に残しダウンロード拒否
- 未設定時は `skipped` として `clean/` へ移動し、ダウンロードを許可する。
  開発・テスト用の既定であり、本番ではスキャナ設定を必須にする。
- 検査ログ（終了コード・出力の先頭500文字）は `scan_note` に保存する。
- 感染ファイルは自動削除せず隔離する。管理者またはアップロード者が削除できる。

## 取得権限
- 社内ユーザー: 同一会社のチケット添付を取得できる。
- 外部ユーザー: 自分が依頼者のチケット添付だけ取得できる。
- `visibility_scope = "global"` のチケットはログインユーザーが取得できる。
- `infected` / `failed` / `pending` は権限があっても取得できない（403）。

## 運用上の注意
- `priv/uploads/` は git 管理外。バックアップ対象に含める。
- スキャナ未設定の `skipped` は「未検査」と表示する。本番で許容しない場合は
  `ATTACHMENT_SCAN_COMMAND` を必須にし、`skipped` を許可しない設定へ変更する。
- 保持期間・自動削除・容量集計は未実装（必要になった時点で追加する）。
