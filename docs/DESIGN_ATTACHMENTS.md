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
- 拡張子・MIME・**実体（マジックバイト）の三点照合**をする（HC-19）。許可する
  拡張子と MIME の組み合わせは `HelpdeskCommander.Attachments.FilePolicy` を
  正本とする。マジックバイト判定は `Attachments.MagicBytes`。
  - 画像: png / jpg / jpeg / gif / webp
  - 文書: pdf / txt / csv / docx / xlsx / pptx
  - 圧縮: zip（OOXML の docx / xlsx / pptx は ZIP ベースのため先頭署名は PK と共有。
    中身の深掘り検査は HC-23）
- 先頭 512 バイトが表示可能テキスト（NUL・制御文字なし。UTF-8 許容）のときは
  テキストと扱い、txt / csv のみ許可する。実行バイナリ等の認識不能な中身は
  どの拡張子でも拒否する（exe を txt にリネームしても通らない）。
- 不一致・判別不能は `:content_magic_mismatch` でアップロードを拒否する。
  拡張子だけ・MIME だけでは通さない。

## ウイルス検査と隔離

実行系統は 2 つ: **clamd サイドカー**（推奨・HC-21）と **スキャナコマンド**（clamscan 等）。
clamd 設定がある場合はコマンドより優先される。
- `ATTACHMENT_SCAN_COMMAND` に `clamscan` などを設定すると、保存したファイルを検査する。
- `ATTACHMENT_SCAN_CLAMD_HOST`（例 `clamd`）を設定すると、コマンドではなく clamd の
  `INSTREAM` で検査する。アプリは Docker ソケットも共有ボリュームも不要で、
  clamd 側の接続失敗・タイムアウト・`ERROR` 応答はすべて `failed` として隔離される。
  構成・起動手順は `docs/SANDBOX_SCANNER.md`。
  - 終了コード 0: `clean` → `clean/` へ移動してダウンロード可
  - 終了コード 1: `infected` → `quarantine/` に残しダウンロード拒否
  - それ以外: `failed` → `quarantine/` に残しダウンロード拒否
- **タイムアウト（HC-16）**: スキャンは既定 30 秒で打ち切り（`ATTACHMENT_SCAN_TIMEOUT_MS` で変更可）、
  `failed` として `quarantine/` に残しダウンロード拒否。
- **fail-closed（HC-16）**: スキャナ異常・未設定・設定不備のいずれも `skipped` にはならず
  `failed` として隔離する。理由は `scan_note` に記録される（未設定は
  `scanner_not_configured`、タイムアウトは `scan_timeout`、設定不備は
  `invalid_scanner_config`）。
- **本番ではスキャナ設定必須（HC-16）**: `config/runtime.exs` が prod の
  `ATTACHMENT_SCAN_COMMAND` 未設定を起動エラーにする。スキャナ未設定を許す
  `skipped` は開発・テスト専用（dev / test の config のみ
  `:attachment_scan_allow_skipped: true`）。本番設定では skipped を許可しない。
- 検査ログ（終了コード・出力の先頭500文字）は `scan_note` に保存する。
- 感染ファイルは自動削除せず隔離する。管理者またはアップロード者が削除できる。

### ClamAV の深掘り検査（HC-23）

`ATTACHMENT_SCAN_COMMAND=clamscan`（basename が `clamscan`）のときは、
`HelpdeskCommander.Attachments.Clamav` が下記の引数を明示的に追加する。

| 分類 | フラグ | 内容 |
| --- | --- | --- |
| 検査対象 | `--scan-archive=yes` `--scan-pdf=yes` `--scan-ole2=yes` `--scan-html=yes` | アーカイブ・PDF・OLE2・HTML を検査 |
| 上限 | `--max-scansize=100M` `--max-filesize=25M` `--max-recursion=16` `--max-files=10000` | ClamAV 既定値を明示。上限超過は exit 2 → `failed` として隔離 |
| 検査不能の可視化 | `--alert-encrypted=yes` `--alert-macros=yes` | 暗号化 ZIP / Office / PDF と OLE2 マクロを検出（exit 1）→ `infected` として隔離 |

- 上限値は `config :helpdesk_commander, :attachment_scan_clamav, max_filesize: "10M", ...`
  で上書きできる（SIZE 表記または整数）。
- 暗号化ファイルとマクロ文書は「検査不能」ではなく「検出」として扱い、隔離する。
  誤検知として解除したい場合は管理者が個別に判断する（HC-20 の範囲）。
- `clamscan` 以外のコマンド（独自ラッパー・`clamdscan` 等）には引数を自動付与しない。
  その場合はラッパー側で同等の設定を行う。
- これらのフラグは ClamAV 0.100 以降を前提とする。導入時は
  `clamscan --help` でフラグの存在を確認する。

## スキャン結果のメタデータ（HC-17）

- `ticket_attachments` に `scan_engine` / `scan_version` / `signature_at` を保存する。
  - ClamAV 指定時は `clamscan --version` の出力（`ClamAV <version>/<sig>/<date>`）から取得。
  - 独自ラッパーは `:attachment_scan_version_command` に `{command, args}` か
    コマンド文字列を設定すると、その出力を同じ形式として解釈する。
  - 取得できない場合は nil（スキャン自体は継続）。
- チケット詳細の添付一覧に「スキャン: ClamAV x.y.z / シグネチャ YYYY-MM-DD HH:MM UTC」を表示する。
- 再検査の判断材料として使う:
  - `signature_at` が再検査時点のシグネチャより古い添付は、新しい定義で再スキャンする
    候補になる（HC-22 の鮮度監視・再スキャンと連動）。
  - 誤検知の解除や監査では `scan_status` / `scan_note` に加えて、このメタデータで
    「どのエンジン・版・定義で判定したか」を確認する。
  - ClamAV はシグネチャ日時をローカル時刻で出力するため、UTC として保存している。
    厳密な時刻比較が必要な場合は運用側の TZ を考慮する。

## 非同期スキャンと再試行（HC-18）

- アップロードは `pending` を返し、`ScanAttachmentWorker`（Oban、queue `attachments`）が
  隔離ディレクトリの実体を非同期に検査する。LiveView がスキャナの完了を待たない。
- 失敗時は上限付き指数バックオフ（`attempt` に応じて 30 秒 → 60 秒 → …、最大 5 分）で
  最大 5 回まで再試行する。5 回失敗すると `failed` のまま隔離される。
- 同じ添付のジョブは Oban の unique（available / scheduled / executing / retryable の間）で
  二重実行しない。既に `clean` / `infected` の添付は再実行しても何もしない（冪等）。
- `failed` の添付は、チケット詳細から**管理者・リーダーまたはアップロード者**が
  「再スキャン」できる。再スキャンはステータスを `pending` に戻して新しいジョブを積む。
- Oban のキューは `attachments: 5`。ワーカー数・再試行回数は `config/config.exs` で調整する。

## シグネチャ更新・鮮度監視・再スキャン（HC-22）

- `UpdateSignaturesWorker`（毎日 03:15）が `freshclam` などを実行し、エンジン・版・
  シグネチャ日時を `attachment_signatures` に保存する。失敗は `status = "error"` として
  記録し、Oban で再試行する。
- 鮮度は `:attachment_signature_max_age_hours`（既定 24 時間）で判定し、stale / 未記録の
  ときは既定で警告ログ、`:attachment_signature_enforce` が true ならアップロードを拒否する。
- 更新成功後、既存の `clean` / `skipped` 添付を `:attachment_rescan_limit`（既定 500）件
  ずつ再スキャンする。対象は pending に戻るため冪等で、enqueue 失敗は `failed` へ隔離する。
- 詳細な運用手順（ブートストラップ・監視項目・バッチの回し方）は
  `docs/OPERATIONS_SCANNER.md` を参照。

## ハッシュ許可・拒否リストと clean キャッシュ（HC-24）

- 管理画面 `/admin/attachment-rules`（管理者のみ）で SHA256 のルールを管理する。
  適用範囲は「自社」または「全体（全社）」、動作は `deny`（拒否）または `allow`（許可）。
- 判定順は **deny > allow > clean キャッシュ > 通常スキャン**。
  - `deny` 一致: スキャンを待たずに `blocked` として隔離（ダウンロード不可）。感染ではないため
    UI では「ブロック」と表示する。
  - `allow` 一致: 拡張子・MIME・マジックバイトの形式検証は維持したままスキャンを省略し
    `clean` として公開する。
  - clean キャッシュ: 同じ SHA256 の添付が **現在のシグネチャ**（engine / version /
    signature_at が一致）で clean 済みなら、スキャンを省略して `clean` にする。
    同じハッシュに infected の記録がある場合と、シグネチャ未記録の場合はキャッシュしない
    （fail-safe）。シグネチャ更新後はキャッシュが無効になり再スキャンされる（HC-22）。
- ルール変更（created / updated / deleted）と判定結果（decision）は監査ログとして
  `Logger` に `audit: "attachment_hash_rules"` のメタデータ付きで記録する。

## 組織固有の YARA 検知（HC-25）

- `priv/yara/*.yar` を版管理し、`ATTACHMENT_YARA_COMMAND`（例: `yara`）で有効化する。
  ルールディレクトリは `ATTACHMENT_YARA_RULES`（既定 `priv/yara`）。
- ClamAV が clean / skipped のとき YARA を実行し、一致があれば `infected` として隔離する。
  `scan_note` に一致ルール名（`YARA: ...`）を残す。YARA の異常終了・タイムアウトは
  `failed` として隔離する。
- ルール追加・更新と再スキャンの手順は `docs/OPERATIONS_SCANNER.md` を参照。

## 感染判定の誤検知解除と監査ログ（HC-20）

- `scan_status == "infected"` の添付は、同一会社の**管理者（`admin`）またはリーダー（`leader`）**
  だけが誤検知として解除できる（`Attachments.override_infected/3`）。一般ユーザー・社外ユーザー・
  他社ユーザーは解除できない。
- 解除には理由（`reason`）の入力を必須とする（空白のみは `:reason_required` で拒否）。
- 解除時は隔離ファイル（`quarantine/`）を `clean/` へ移動し、`scan_status` を `clean`、
  `scan_note` に `false_positive_override: <理由> / previous: <元ノート>` を記録する。
- 監査イベントとして `TicketEvent`（`event_type: "attachment_quarantine_overridden"`）を作成し、
  実行者（`actor_id`）、対象添付 ID・ファイル名・SHA256、解除理由、変更前後の状態
  （`from_status: "infected"`, `to_status: "clean"`, `previous_scan_note`, `scan_engine`, `scan_version`）
  を永続化する。チケット詳細のイベントログから確認できる。

## 取得権限
- 社内ユーザー: 同一会社のチケット添付を取得できる。
- 外部ユーザー: 自分が依頼者のチケット添付だけ取得できる。
- `visibility_scope = "global"` のチケットはログインユーザーが取得できる。
- `infected` / `failed` / `pending` は権限があっても取得できない（403）。

## 運用上の注意
- `priv/uploads/` は git 管理外。バックアップ対象に含める。
- `skipped` の表示は「未検査」。本番（HC-16 以降）では fail-closed 運用のために
  `skipped` は発生しない（スキャナ未設定なら起動しない）。
- スキャナのタイムアウトは `ATTACHMENT_SCAN_TIMEOUT_MS`（既定 30000）。ClamAV の
  大きなアーカイブを扱う場合は余裕を持たせる。
- 保持期間・自動削除・容量集計は未実装（必要になった時点で追加する）。
