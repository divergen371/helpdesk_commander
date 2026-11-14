# 検出品質の評価（HC-26）

ClamAV シグネチャとスキャナ設定の効果を、感覚ではなく数値で比較するための評価基盤。
安全な検体コーパスを `Scanner.scan/1` に通し、検出率・誤検知率・スキャン時間を計測して
合格基準で判定する。

評価するのは `Scanner.scan/1` の範囲（ClamAV / clamd / スキャナコマンド）だけ。
YARA は `Attachments.scan_result/1` の後段で走るため、このハーネスでは測らない。
アップロードのルーティング・隔離・DB 更新も対象外（それぞれのテストで担保する）。

## コーパス

`priv/eval/corpus/` に配置し、`manifest.json` がラベルを持つ。

| 種別 | サンプル |
| --- | --- |
| malicious | `eicar.txt`（EICAR 標準テストファイル）、`eicar.zip`（ZIP 内 EICAR）、`eicar.pdf`（PDF 内 EICAR） |
| benign | テキスト、空ファイル、最小 PDF、PNG ヘッダー、ZIP、JSON、CSV |

- 実マルウェアは置かない。EICAR と良性ファイルだけを使う。
- サンプルを追加するときは `manifest.json` に `path` / `label` / `description` を追記する。

## メトリクス

| 指標 | 定義 |
| --- | --- |
| 検出率 | malicious のうち `infected` になった割合 |
| 誤検知率 | benign のうち `infected` になった割合 |
| エラー率 | `{:error, _}` になった割合 |
| 平均 / p95 スキャン時間 | `Scanner.scan/1` の実測値（ms） |

レポートは `eval/detection_report.json` に出力し、CI では job summary にも表を出す。

## 合格基準

`priv/eval/baseline.json`:

```json
{
  "min_detection_rate": 95.0,
  "max_false_positive_rate": 5.0,
  "max_error_rate": 0.0,
  "max_p95_ms": 2000.0
}
```

- 1 つでも外れると `run_corpus.exs` は exit 1。
- 基準を下げない。改善して安定したら上げる。
- 一時的な確認は `EVAL_BASELINE=<path>` で別の基準ファイルを指定できる。

## 実行

```bash
# CI と同じ（決定的なスタブスキャナ。EICAR のみ検出）
EVAL_SCANNER=stub mix run --no-start priv/eval/run_corpus.exs

# 実 clamd で評価（サンドボックス構成。docs/SANDBOX_SCANNER.md）
ATTACHMENT_SCAN_CLAMD_HOST=127.0.0.1 \
ATTACHMENT_SCAN_CLAMD_PORT=3310 \
EVAL_SCANNER=real \
mix run --no-start priv/eval/run_corpus.exs
```

- `stub` は `priv/eval/stub_scanner.sh` を使う。CI と開発で同じ結果になる。
- `real` は設定済みの clamd（または `ATTACHMENT_SCAN_COMMAND`）を使う。実エンジンの
  検出率を見たいときはこちらを使う。
- `mix run --no-start` なので DB は不要。

## 変更前後の比較

1. 変更前に実 clamd で実行し、レポートを保存する

   ```bash
   EVAL_SCANNER=real mix run --no-start priv/eval/run_corpus.exs
   cp eval/detection_report.json eval/before.json
   ```

2. シグネチャ更新・YARA 追加・設定変更を行う
3. 再度実行し、`detection_rate` / `false_positive_rate` / `p95_ms` を比較する
4. 合格基準を満たすことと、検出率が下がっていないことを確認する

CI のスタブ実行は「評価ハーネスとコーパスの回帰」の確認であり、実エンジンの検出力では
ない。実エンジンの比較は上記の手順で行う。

## CI / 定期実行

- CI: `.github/workflows/ci.yml` の `detection-corpus` job（PR と main push）
- 夜間: `.github/workflows/quality-nightly.yml`
- レポート: `eval/` を artifact に保存、job summary にメトリクス表を表示
- 失敗時は job が失敗し、マージを止める（必須チェックは `Quality gate summary`）

## 限界

- コーパスは小さい。検出率 100% は「このコーパスで見逃さない」以上の意味を持たない。
- EICAR は ClamAV のテスト用シグネチャであり、実マルウェアの検出力を代表しない。
- YARA ルールの追加・変更はこのコーパスでは検出されない。YARA は別途テストで検証する。
- スタブ実行はスキャナ呼び出しとタイミングの回帰確認用。ルーティング・隔離は対象外。
- 実エンジンの評価は clamd のシグネチャ鮮度に依存する（`signature_at` を確認する）。
