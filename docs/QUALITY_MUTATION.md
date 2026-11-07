# 変異テストの評価（HC-38）

テストの「検出力」を測るため、変異テストツールを 1 モジュールで試験実行した。
結論: **全モジュールを CI で回さない。対象を高リスク領域に限定して導入する（HC-39）**。

## 候補

| ツール | 方式 | 特徴 |
| --- | --- | --- |
| **mutare** | compile-once（メタミュータント） | 高速。`--since` で差分限定、`# mutare:ignore`、複数レポート |
| Muex | mutant ごとにコンパイル | 成熟。`--preset phoenix/ecto/ash`、`--coverage-guided` |
| mutalisk | Stryker 互換 | concurrency、履歴、Stryker JSON |
| muta | alpha | シンプル。1 ファイル + テスト指定 |

`mutare` を採用して試験した（コンパイル 1 回で高速、差分限定が可能）。依存解決のため
`sourceror` を 1.12.4 に下げる必要があった（1.13.0 は mutare 0.5 の制約外）。

## 試験結果（2026-11-07）

対象: `lib/helpdesk_commander/support/company_code.ex`（40 行）

```bash
MIX_ENV=test mix mutare --only lib/helpdesk_commander/support/company_code.ex
```

| 指標 | 値 |
| --- | --- |
| mutants | 37 |
| killed | 32 |
| survived | 5 |
| mutation score | 86.5% |
| 実行時間 | 約 55 秒（1 モジュール、ベースライン含む） |

検出されたテスト不足（例）:

- `normalize/1` / `hash/1` / `hash!/1` の `when is_binary(code)` を外してもテストが通る
  （非バイナリ入力の挙動を検証していない）
- `hash!/1` の `ArgumentError` メッセージを変更してもテストが通る（文言を検証していない）

## 判断

- **全 lib の一括実行は行わない**。`mix mutare`（引数なし）は Ash のマクロ展開で失敗し、
  仮に動いても全体では実行時間が大きすぎる。
- 高リスク領域（認証・添付・権限）に対象を限定し、PR 差分（`--since`）またはモジュール指定で
  CI に組み込む。しきい値と実行時間上限は HC-39 で決める。
- 等価 mutant と許容するものは `# mutare:ignore` と理由で管理する（無言の除外をしない）。

## ローカル実行

```bash
# 依存（dev/test のみ）
mix deps.get

# 1 モジュール
MIX_ENV=test mix mutare --only lib/helpdesk_commander/support/company_code.ex

# 差分のみ
MIX_ENV=test mix mutare --since main

# スコア下限で失敗させる
MIX_ENV=test mix mutare --only <file> --min-score 80
```

- CI にはまだ組み込んでいない。組み込みは HC-39。
- `sourceror` のバージョン制約（mutare 0.5 は `~> 1.12.3`）に注意する。
