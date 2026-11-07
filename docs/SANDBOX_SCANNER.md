# サンドボックス化されたスキャナ（clamd）— HC-21

スキャナ自体が攻撃面にならないよう、検査を専用コンテナへ隔離する構成。
アプリは Docker ソケットを持たず、TCP の `INSTREAM` だけで clamd に話しかける。

## 1. 必要性

`ATTACHMENT_SCAN_COMMAND=clamscan` 方式は、アプリと同じ特権・同じファイルシステムで
スキャナプロセスを fork する。悪意ある添付を解析中の ClamAV 脆弱性が使われれば、
アプリの権限でホストに届く。そこで検査だけを分離し、以下を clamd 側だけで満たす:

- 外部ネットワークなし（`internal: true` のネットワークに隔離）
- 読み取り専用 rootfs（書き込みは tmpfs とシグネチャ DB ボリュームのみ）
- 非 root（`clamav` uid 100 / gid 101）
- capability を全て drop（`cap_drop: ALL`）+ `no-new-privileges`
- メモリ / CPU / プロセス数の上限

Elixir/Erlang には seccomp・Landlock を扱う成熟したライブラリがなく、MuonTrap は
cgroup 制限しか提供しないため、分離はコンテナ管理側（Docker）に持たせる。

## 2. 構成

```
app (Elixir)  -- TCP 3310 / INSTREAM -->  clamd (scanner_internal, read-only)
                                                   ^
clamav-db-updater (egress あり)  -->  clamav_signatures volume（DB のみ共有）
```

- `docker/clamav/Dockerfile`: Alpine 3.22 + `apk add clamav`（ClamAV 1.4.x）。
  arm64 / amd64 対応、`clamav` ユーザー入り。
- `docker/clamav/clamd.conf`: 深掘り検査（archive / pdf / ole2 / xml / html）、
  上限（`MaxScanSize` 等は clamd.conf で受理されるものだけを列挙）、
  `AlertEncrypted* yes` / `AlertOLE2Macros` 相当 / `AlertExceedsMax yes`。
  → 暗号化・上限超過は検出（`infected`）扱いで黙って通さない。
- `docker/clamav/freshclam.conf`: db-updater 専用。clamd 本体は egress を持たない。
- `docker-compose.yml`: サービス `clamd`（`scanner_internal` のみ・ポート公開なし）と
  `clamav-db-updater`（`helpdesk_network` のみ）。

## 3. アプリ側の設定

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `ATTACHMENT_SCAN_CLAMD_HOST` | なし | 設定すると clamd 利用に切り替わる（コマンドより優先） |
| `ATTACHMENT_SCAN_CLAMD_PORT` | 3310 | clamd の TCP ポート |

clamd を使う場合も HC-16 の fail-closed は同じ:

- 接続失敗 → `{:error, {:clamd_connect, reason}}` → `failed` 隔離
- タイムアウト（`ATTACHMENT_SCAN_TIMEOUT_MS`、既定 30 秒）→ `{:error, :clamd_timeout}` → `failed` 隔離
- `ERROR` 応答 → `{:error, {:clamd_error, reason}}` → `failed` 隔離
- 本番で `ATTACHMENT_SCAN_COMMAND` と `ATTACHMENT_SCAN_CLAMD_HOST` の両方が未設定なら起動しない

エンジン情報（HC-17）は clamd の `VERSION` から取得する。`UpdateSignaturesWorker`
（HC-22）は clamd 設定時、`freshclam` 実行の代わりに `RELOAD` を発行して DB を取り込み、
`VERSION` からシグネチャ日時を記録する。

## 4. 検証

```bash
# コンテナ起動（ローカル開発では dev オーバーライドで 127.0.0.1:3310 を公開する）
docker compose -f docker-compose.yml -f docker-compose.clamd-dev.yml up -d clamav-db-updater clamd

# clamd 疎通 + EICAR（clean / infected の両方を確認）
ATTACHMENT_SCAN_CLAMD_HOST=127.0.0.1 mix run priv/verify/verify_clamd.exs
```

`priv/verify/verify_clamd.exs` は PING → VERSION → 良性ファイル → EICAR 検体の順に確認し、
1 つでも失敗すれば非ゼロで終了する。実装単体テストは
`test/helpdesk_commander/attachments/clamd_test.exs` が clamd 互換の偽サーバーで
プロトコル・タイムアウト・ERROR 応答まで検証する（CI に clamd は不要）。

## 5. 制約と次の課題

- dev オーバーライド（`docker-compose.clamd-dev.yml`）はホストから届くよう egress を
  解禁する開発専用の緩和策。本番では使わない。
- Alpine の ClamAV 1.4.x の clamd.conf は一部のオプション（`MaxSpace` など）を
  受理しない。追加するときは起動ログの `Unknown option` を確認する。
- YARA（HC-25）はアプリ側コマンドのまま。サンドボックス化は clamd のみ。
- seccomp プロファイルの追加（`security_opt`）は未実施。
