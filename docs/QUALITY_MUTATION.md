# 変異テスト（HC-38 / HC-39）

テストの「検出力」を測るため、変異テストを高リスクモジュールに限定して CI に導入した。
全モジュールの一括実行は行わない（Ash マクロの変換失敗と実行時間のため）。

## 候補

| ツール | 方式 | 特徴 |
| --- | --- | --- |
| **mutare** | compile-once（メタミュータント） | 高速。`--since` で差分限定、`# mutare:ignore`、複数レポート |
| Muex | mutant ごとにコンパイル | 成熟。`--preset phoenix/ecto/ash`、`--coverage-guided` |
| mutalisk | Stryker 互換 | concurrency、履歴、Stryker JSON |
| muta | alpha | シンプル。1 ファイル + テスト指定 |

`mutare` を採用。依存解決のため `sourceror` を 1.12.4 に下げている
（1.13.0 は mutare 0.5 の制約外）。

## CI の対象としきい値（HC-39）

`priv/ci/run_mutation.sh` が次の 4 モジュールを実行する。

| モジュール | 下限 | 現在 | mutants |
| --- | --- | --- | --- |
| `lib/helpdesk_commander/authorization.ex` | 95% | 100% | 47 |
| `lib/helpdesk_commander/attachments/file_policy.ex` | 95% | 100% | 81 |
| `lib/helpdesk_commander/support/pii_hash.ex` | 95% | 100% | 21 |
| `lib/helpdesk_commander/support/company_code.ex` | 95% | 100% | 37 |

- **トリガー**
  - PR: `--since origin/<base>` で**変更行のみ**（`MUTATION_SINCE` を CI が設定）
  - `main` への push と夜間: 全量
- **実行時間**: 全量で約 8 分。CI ジョブのタイムアウトは 15 分。
  PR は差分限定のため通常は数分。
- **失敗条件**: いずれかのモジュールが下限 95% を下回ると失敗。
- **レポート**: not covered の mutant はスコアの分母から除外される。

## 等価 mutant と許容の管理

- 等価・許容する mutant はソース中の `# mutare:ignore[family] 理由` で除外する。
  無言の除外はしない。
- 現在の ignore（すべて等価）:
  - `Authorization.privileged_role?/1` / `external?/1` の `guard_drop`
    （非バイナリは `in` で false になり、ガード削除と同値）
  - `Authorization.same_company?/2` の `not is_nil(company_id)`
    （`company_id` はスキーマで必須のため等価）
  - `PiiHash.email/1` / `company_name/1` / `normalize/1` の `guard_drop`
    （非バイナリは `String.trim` で例外になり同値）
  - `CompanyCode.normalize/1` / `hash/1` / `hash!/1` の `guard_drop`
    （非バイナリは `String.trim` / `:crypto.mac` が拒否するため同値）

## 変異テストで見つけて解消したテスト不足

- PII 正規化の trim / downcase（`PiiHash` のハッシュ一致）
- 認可の非バイナリ入力と `same_company?` の会社不一致
- 形式検証の大文字拡張子・MIME パラメータ・前後空白・10MB 境界・欠損ファイル・
  upload 以外の値
- `CompanyCode.hash!` の例外メッセージ

## ローカル実行

```bash
# 依存（dev/test のみ）
mix deps.get

# CI と同じ 4 モジュール
bash priv/ci/run_mutation.sh

# 1 モジュール
MIX_ENV=test mix mutare --only lib/helpdesk_commander/authorization.ex

# 差分のみ
MUTATION_SINCE=origin/main bash priv/ci/run_mutation.sh

# スコア下限で失敗させる
MIX_ENV=test mix mutare --only <file> --min-score 95
```

## 対象モジュールを追加する手順

1. ローカルで `mix mutare --only <file> --min-score 0` を実行する。
2. スコアと survivor を確認する。等価なものは理由付きで `# mutare:ignore` にする。
   実ギャップはテストを追加する。
3. 安定したスコアから 5pt 程度下を下限にして `priv/ci/run_mutation.sh` に追加する。
4. 実行時間を測り、CI の 15 分以内に収まることを確認する。

## 制約

- `mix mutare`（引数なし）は Ash のマクロ展開で失敗するため、必ずファイル指定する。
- 変異テストはテストの検出力を測るものであり、カバレッジやレビューの代替ではない。
- `sourceror` のバージョン制約（mutare 0.5 は `~> 1.12.3`）に注意する。
