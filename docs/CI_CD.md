# CI/CD ガイド

## 📋 概要

このプロジェクトでは GitHub Actions を使って CI を実行します。  
`main` への push と、`main` / `archetype/**` への PR で動作します。

**docs-only（`*.md` / `docs/*.md`）のみ変更の場合は CI をスキップ**します。

## 🔧 使用技術

- **CI/CDプラットフォーム**: GitHub Actions
- **Elixir**: 1.20.4
- **Erlang/OTP**: 29.1.2
- **PostgreSQL**: 18 (Alpine)
- **Assets**: `mix tailwind.install` / `mix esbuild.install` → `mix assets.deploy`

## 🎯 ワークフロー構成

### 1. Coverage Job

**目的**: テストとカバレッジのラチェット判定

**実行内容**:
- PostgreSQL 18 の起動（Service）
- `mix deps.get`
- `mix deps.compile`
- `mix coveralls.json`
- `mix run --no-start priv/ci/check_coverage.exs`
  - `priv/ci/coverage_baseline.txt`（現在 82.0%）と絶対下限 80% を下回ると失敗
- `cover/` を artifact として保存

### 2. Precommit Job

**目的**: `mix precommit` と migration 差分の検証

**実行内容**:
- PostgreSQL 18 の起動（Service）
- `mix deps.get`
- `mix deps.compile`
- `mix precommit`（compile `--warnings-as-errors` / format / credo strict / test）
- `mix ash.codegen --check`
- `mix sobelow`（Phoenix セキュリティ静的解析）

### 3. Dialyzer Job

**目的**: 型チェック

**実行内容**:
- `priv/plts` をキャッシュ
- `mix dialyzer --format github`
- **Old PLT 対策**: 失敗時に `dialyzer.plt` と `.hash` を削除 → `mix dialyzer --plt` で再生成

### 4. Assets Job

**目的**: アセットビルドの確認

**実行内容**:
- `mix deps.get`
- `npm ci --prefix assets`
- `mix tailwind.install --if-missing`
- `mix esbuild.install --if-missing`
- `mix assets.deploy`
- `priv/static/assets/js/app.js` / `css/app.css` の存在確認

> `SECRET_KEY_BASE` は CI で固定値を使用しています。

### 5. Audit Job

**目的**: 依存関係と既知脆弱性の監査

**実行内容**:
- `mix hex.audit`（retired / advisory）
- `mix deps.audit`（GitHub Advisory）
- `mix run --no-start priv/ci/check_audit.exs`（allowlist 判定）
- `npm audit --omit=dev --audit-level=high --prefix assets`

週次（毎週月曜 04:00 UTC）は `.github/workflows/security-audit.yml` で同じ監査を実行する。
allowlist の書式と更新手順は `docs/QUALITY_DEPENDENCIES.md` を参照。

夜間（毎日 03:00 UTC）は `.github/workflows/quality-nightly.yml` がテスト・カバレッジ・
メトリクス・Dialyzer・依存監査をまとめて実行する。カバレッジ 0.3pt 超の低下または
テスト数の減少で失敗し、`quality-metrics.json` を artifact に保存する。Sobelow と依存監査も
同じジョブで実行する。
詳細は `docs/QUALITY_GATES.md`。

### 6. Summary Job

**目的**: 全ゲートの結果を job summary に集約する

**実行内容**:
- `coverage` / `precommit` / `dialyzer` / `assets` / `audit` の結果を表で `$GITHUB_STEP_SUMMARY` に出力
- いずれかが失敗・キャンセルなら Summary Job も失敗し、マージを止める

## 📊 ワークフロー詳細

### トリガー条件

```yaml
on:
  push:
    branches: [main]
    paths-ignore:
      - "*.md"
      - "docs/*.md"
  pull_request:
    branches:
      - main
      - "archetype/**"
    paths-ignore:
      - "*.md"
      - "docs/*.md"
```

### 環境変数

```yaml
env:
  MIX_ENV: test
  ELIXIR_VERSION: "1.20.4"
  OTP_VERSION: "29.1.2"
```

### キャッシュ戦略

- **依存関係**: `deps/` と `_build/` を `mix.lock` でキャッシュ
- **Dialyzer PLT**: `priv/plts` を `mix.lock` でキャッシュ

## 🚀 ローカルでの実行

```bash
# まとめて実行（format / compile / credo / test + codegen + dialyzer）
mix quality

# カバレッジのラチェット判定まで含める
mix quality.coverage

# CIと同等の個別実行
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix ash.codegen --check
mix dialyzer
mix coveralls.json
mix run --no-start priv/ci/check_coverage.exs
```

### カバレッジ閾値

- `priv/ci/coverage_baseline.txt` のラチェット基準（現在 82.0%）と、スクリプト内の
  絶対下限 80% で判定する。
- CI では `cover/` を artifact として保存する。
- 詳細は `docs/QUALITY_GATES.md` を参照。
```

## 🔍 トラブルシューティング

### Dialyzer が Old PLT で失敗する

```bash
rm -f priv/plts/dialyzer.plt priv/plts/dialyzer.plt.hash
mix dialyzer --plt
mix dialyzer
```

### Assets Job が失敗する

```bash
mix tailwind.install --if-missing
mix esbuild.install --if-missing
mix assets.deploy
```

## 📚 参考リンク

- [GitHub Actions ドキュメント](https://docs.github.com/ja/actions)
- [erlef/setup-beam](https://github.com/erlef/setup-beam)
- [actions/cache](https://github.com/actions/cache)
