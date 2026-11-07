# 品質ゲート（HC-33）

PR とローカルで同じ判定になるよう、品質ゲートを一本化する。CI の正本は
`.github/workflows/ci.yml`、カバレッジの基準は `priv/ci/coverage_baseline.txt`。

## ローカルと CI の対応

| ゲート | ローカル | CI（job） | 失敗時 |
| --- | --- | --- | --- |
| compile（警告をエラー化） | `mix precommit` | precommit | ブロック |
| format | `mix precommit` | precommit | ブロック |
| Credo（strict） | `mix precommit` | precommit | ブロック |
| テスト | `mix precommit` | precommit / coverage | ブロック |
| Ash codegen 差分 | `mix ash.codegen --check` | precommit | ブロック |
| Dialyzer | `mix dialyzer` | dialyzer | ブロック |
| カバレッジ・ラチェット | `mix quality.coverage` | coverage | ブロック |
| アセットビルド | `mix assets.deploy` | assets | ブロック |
| 依存監査 | `mix hex.audit` / `mix deps.audit` / `priv/ci/check_audit.exs` | audit | ブロック |
| 品質メトリクス（夜間） | `TEST_COUNT=<n> mix run --no-start priv/ci/quality_metrics.exs` | quality-nightly | ブロック |
| Phoenix セキュリティ（Sobelow） | `mix sobelow` | precommit / quality-nightly | ブロック |

依存監査の詳細は `docs/QUALITY_DEPENDENCIES.md`、Sobelow のトリアージ方針は
`docs/QUALITY_SECURITY.md`。

まとめて実行する場合:

```bash
mix quality            # precommit + ash.codegen --check + dialyzer
mix quality.coverage   # coveralls.json + ラチェット判定
```

`mix precommit` は compile（`--warnings-as-errors`）/ format / credo strict / test を実行する。

## カバレッジのラチェット

- `priv/ci/coverage_baseline.txt` の数値（現在 82.0%）を下限とする。
- 絶対下限は 80%（`priv/ci/check_coverage.exs` の `@absolute_minimum`）。
- 判定は `mix coveralls.json` が出力する `cover/excoveralls.json` を使う。
- 基準を下げない。カバレッジが改善して安定したら、基準値を手で上げる。
- 一時的な検証は `COVERAGE_BASELINE=99 mix quality.coverage` のように上書きできる。

## 夜間の品質回帰チェック（HC-36）

`.github/workflows/quality-nightly.yml` が毎日 03:00 UTC（手動実行も可）に実行する。

- テスト（件数を記録）、format、credo strict、`ash.codegen --check`、カバレッジとラチェット
- `priv/ci/quality_metrics.exs` でカバレッジとテスト数を
  `priv/ci/quality_baseline.json` と比較する
  - カバレッジの低下が 0.3pt を超える、またはテスト数が減ると失敗
- Dialyzer、依存監査（hex.audit / deps.audit / allowlist）、npm audit
- `quality-metrics.json` / `test_output.log` / `cover/` を artifact に保存

ベースライン（`priv/ci/quality_baseline.json`）は、改善して安定したときだけ手で更新する。
下げない。夜間ジョブが失敗したら、artifact のログと metrics を確認し、原因を修正してから
再実行する。

```bash
# ローカルで同じ判定（カバレッジ計測後）
TEST_COUNT=438 mix run --no-start priv/ci/quality_metrics.exs
```

## job summary

CI の `summary` job が全ゲートの結果を GitHub の job summary に表で出す。
`coverage` / `precommit` / `dialyzer` / `assets` のいずれかが失敗またはキャンセルなら
`summary` job も失敗し、マージを止める。

## ゲートが実際に落ちることの確認（2026-11-07）

各ゲートを一時的に壊して、非ゼロ終了になることを確認した（検証後に復元）。

| 壊し方 | コマンド | 終了コード |
| --- | --- | --- |
| 整形されていないファイルを追加 | `mix format --check-formatted` | 1 |
| 未使用変数を含むファイルを追加 | `mix compile --warnings-as-errors` | 1 |
| Credo 指摘のあるファイルを追加 | `mix credo --strict` | 4 |
| 失敗するテストを追加 | `mix test` | 2 |
| リソースに属性を追加して migration 未生成 | `mix ash.codegen --check` | 1 |
| `@spec` と戻り値が不一致 | `mix dialyzer` | 2 |
| 基準値を 99% に上書き | `mix run --no-start priv/ci/check_coverage.exs` | 1 |

実際の PR での失敗確認は、次に CI を変更する PR で行う（ローカルで同一コマンドの
失敗を確認済み）。

## トラブルシューティング

- Dialyzer が Old PLT で失敗する: `rm -f priv/plts/dialyzer.plt priv/plts/dialyzer.plt.hash && mix dialyzer --plt`
- カバレッジが基準を下回る: テストを追加する。基準値を下げない。
- `mix ash.codegen --check` が失敗する: `mix ash.codegen <name>` で migration を生成し、
  内容をレビューしてからコミットする。
- CI だけ失敗する: `mix quality` と `mix quality.coverage` をローカルで実行し、
  CI と同じコマンドで再現する。
