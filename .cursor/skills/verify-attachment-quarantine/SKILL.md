---
name: verify-attachment-quarantine
description: "Use when a change touches attachment ingest, scanning, storage promotion, rescan sweeps, or the infected override in helpdesk_commander. Checks the quarantine lifecycle model with TLC and tells a real bug from modeling drift."
---

# 添付ファイル検疫ライフサイクルの形式検証

## 何を保証するか

**性質 1（安全性・配信）**: ダウンロード可能な添付（`scan_status` が `clean` か `skipped`）のとき、配信される実体は `clean/` にあり、そのバイトは `clean` と判定されている。

**害**: 破れると、スキャンで感染と判定されたバイト、または一度も検査していないバイトが利用者に配信される。ウイルス配布とデータ持ち出しに直結する。

**性質 2（安全性・隔離）**: 感染と判定されたバイトは配信ディレクトリ（`clean/`）に置かず、解除（同一会社の管理者による理由付き）以外の経路で `clean` 状態にならない。

**性質 3（安全性・隔離）**: スキャンが失敗した添付のバイトも配信ディレクトリに残さない。

**害**: 性質 2・3 が破れると、状態フィールド 1 つを頼りに感染バイトが配信ディレクトリに同居する。状態が誤って `clean` に戻る経路（解除・再同期・手作業）が生じた瞬間に配信される。

**性質 4（可用性・掃引、ExUnit が担保）**: 一度 `clean` と判定された添付は、`rescan_outdated/1` の掃引後の再スキャンでも `clean` のまま配信できる。

**害**: 破れると、シグネチャ更新後の一括再スキャンが健全な添付を軒並み `failed` にして配信停止にする。この性質は「同じバイトを同じシグネチャで読み直せば同じ判定」という決定性に依存するため TLA+ では抽象化し、`test/helpdesk_commander/helpdesk/attachments_rescan_storage_test.exs` で固定している。

## 対象コード（coverage）

| ファイル | 関数 |
| --- | --- |
| `lib/helpdesk_commander/helpdesk/attachments.ex` | `ingest/3`, `create_with_status/6`, `place_created/2`, `scan_attachment/1`, `scan/1`, `scan_source/1`, `place_bytes/3`, `rescan/2`, `rescan_outdated/1`, `rescan_existing/1`, `override_infected/3`, `downloadable?/1`, `download_path/1` |
| `lib/helpdesk_commander/attachments/storage.ex` | `store/3`, `promote/1`, `demote/1`, `resident?/2`, `path/2` |
| `lib/helpdesk_commander/workers/scan_attachment_worker.ex` | `perform/1`, `backoff/1` |

**sync commit**: `abf6eba`（このスキルを最新化したコミット。修正本体は `e6c4f93`、許可リスト経路とモデルの同期は `abf6eba`）
このコミット時点で、下のモデルが上記コードを記述していることを確認済み。**covered のコードが変わったら、まずこのスキルの「更新手順」を読む。確認するまで sync commit を進めない。**

## 実行

```bash
cd spec && JAR="$(mise where 'http:tla2tools@1.7.4')/tla2tools.jar" && java -XX:+UseParallelGC \
  -cp "$JAR" tlc2.TLC -config attachment_lifecycle.cfg -deadlock attachment_lifecycle.tla
```

- ツールはリポジトリで固定済み: `.tool-versions` に `http:tla2tools 1.7.4` と `java temurin-25.0.5.1+2.0.LTS`。fresh checkout では `mise install` だけで揃う
- jar のパスを本文に直書きしない（`mise where` で解決する。バージョンを上げたら `.tool-versions` も更新する）
- 状態数は 27 程度、実行は 1 秒未満
- 安全性だけを見たいとき: `-config attachment_lifecycle.safety.cfg`（性質 1 のみ。他は全性質の cfg で見る）

TLA+ の結果は必ず `/statechart` スキルで読む。違反は最短経路の手順として、通過時は状態遷移図として出る。`/statechart` のコマンドやパスはリリースごとに変わるので、このスキルに写さない。

## モデルと現実の対応

`spec/attachment_lifecycle.tla` は 1 添付・1 レコードを状態として持つ。

| モデル | コード |
| --- | --- |
| `status` | `TicketAttachment.scan_status`（`pending` / `clean` / `infected` / `failed`） |
| `loc` | 実バイトの置き場所。`Storage.store/3` が `quarantine/` に複製し、`Storage.promote/1` が `File.rename` で `clean/` へ**移動**する |
| `verdict` | 現在 `loc` にあるバイトに対して最後に得られた判定 |
| `Ingest` | `ingest/3`（`pending` + `quarantine/`） |
| `IngestKnownClean` | 許可リスト・キャッシュヒット経路（`create_with_status/6` → `place_created/2`）。既知の clean として作り `promote/1` |
| `IngestKnownCleanPromoteFails` | 同じ経路で `promote/1` が失敗 → `clean` を書かず `failed`（`storage_promote_failed`） |
| `WorkerScanCleanFromQuarantine` | `scan/1` が clean → `place_bytes/3` が `promote/1` → `mark_scan` で `clean` |
| `WorkerScanCleanFromClean` | 実体が既に `clean/`（掃引後の再スキャン）。読み直して clean なら置き直しは不要 |
| `WorkerScanInfectedFromQuarantine` | `scan/1` の感染側。実体は `quarantine/` のまま |
| `WorkerScanInfectedFromClean` | 再スキャンで感染を検知。`Storage.demote/1` で `quarantine/` へ戻してから `infected` を書く |
| `WorkerScanErrorFromQuarantine` / `FromClean` | `Scanner` のエラー。同じく非配信なので実体は `quarantine/` に置く |
| `PlaceFailed` | `place_bytes/3` の失敗（mkdir・rename エラー）。`clean` を書かず `failed` にする |
| `Sweep` | `rescan_outdated/1`。`clean` → `pending`、実体には触らない |
| `AdminRescan` | `rescan/2`。`failed` → `pending` |
| `Override` | `override_infected/3`。`promote/1` + `clean` 書き込み（監査イベント付き） |

## 前提と限界

- 1 添付のみをモデル化している。複数添付間の干渉（同一 `storage_key` の衝突など）は対象外
- `skipped` は本番で発生しない前提（`config/runtime.exs` がスキャナ未設定で起動を止める）。開発・テストで `attachment_scan_allow_skipped` を true にした場合は「全ファイルが未検査で配信可能」になるため、モデルより弱い安全性になる
- YARA は「感染を返し得る経路」として `WorkerScanInfected` に畳んでいる。ClamAV と YARA の順序そのものは検証していない
- DB トランザクションの失敗・ロールバック、Oban の at-most-once 性、`unique` 制約の実効性はモデル化していない（`loc` と `status` の書き込みが不可分であると仮定）
- 監査イベント（`TicketEvent`）の記録は検証対象外
- 外部要因による実体削除・ディスク障害はモデル化していない（`loc` は常にどちらかに存在すると仮定）。実体消失の扱いは ExUnit の `missing_storage` テストが担保する

## 解消済みの所見（履歴）

**2026-11-28、`e6c4f93` で修正済み**: 旧 `scan/1` は常に `quarantine/` を開いていたため、一度 `clean` になった（`promote/1` で `clean/` へ移動済みの）添付は、`rescan_outdated/1` の掃引後に再スキャンすると実体を見つけられず `failed` に落ちていた。TLC の反例は 4 ステップ:

1. `ingest/3` が `pending` で `quarantine/` に実体を置く
2. `scan/1` が clean を返し、`promote/1` が実体を `clean/` へ rename、`status = clean`
3. `rescan_outdated/1` が `status` を `pending` に戻す（実体は動かさない）
4. `scan/1` が `quarantine/` を開こうとして失敗し、`status = failed`

実コードでも再現した（`scan_note = "{:exit_status, 2, nil}"`、`downloadable?/1` は false、実体は `clean/` に残存）。既定 500 件/回で健全な添付が配信停止になっていた。

修正内容: `scan_source/1` が実体を `quarantine/` → `clean/` の順に探す、`place_bytes/3` が非配信時に `Storage.demote/1` で隔離へ戻す、置き直し失敗は `clean` を書かず `failed`、`rescan_existing/1` は実体消失を `failed`（`missing_storage`）にする。

再発防止: `test/helpdesk_commander/helpdesk/attachments_rescan_storage_test.exs`（5 件）。**この所見を再現するコードに戻すと、このテストと TLA+ の `FailedBytesQuarantined` が同時に落ちる。**

**同じクラスの 2 箇所目（`abf6eba` で修正）**: 許可リスト・キャッシュヒットで既知の clean として作る `create_with_status/6` も `Storage.promote/1` の戻り値を捨てていた。promote に失敗しても `clean` を名乗るため、`downloadable?/1` は true、`download_path/1` は存在しない `clean/` パスを返していた。`place_created/2` で `failed`（`storage_promote_failed`）に落とし、回帰テストを 1 件追加（`clean/` を `0o500` にして EACCES を起こす）。モデルにも `IngestKnownClean` / `IngestKnownCleanPromoteFails` として現れている。

## 更新手順（drift を直すとき）

1. 上の「対象コード」が最後に変わったコミットを `git log -1 -- <path>` で確認し、その差分を読む
2. 差分ごとに「無影響 / モデルが記述を失った / 約束が意図的に変わった / 約束が破られた疑い」を判定する。**結果を見てからモデルを合わせない**。コードを読んでからモデルを直す
3. 1 つの不可分な処理はモデルでも 1 ステップにする。分岐やチェックが増えたらアクションを増やすか前提を足す
4. 直したら再実行し、緑なら**わざと壊して**（例: `promote` せず `clean` を書くアクションを足す）性質が落ちることを確認してから戻す
5. 赤なら、反例の各ステップが実コードで起こり得るかを確かめる。起こり得ないならモデルの誤り、起こり得るならバグ。バグは製品コードを直さず報告する
6. ここまで済んでから sync commit を更新する

## 変更が意図的だった場合

性質そのものを変えるときは、旧文面・新文面・根拠（doc コメント / テスト / コミットメッセージ）をこのスキルに残す。根拠なしに性質を弱めない。
