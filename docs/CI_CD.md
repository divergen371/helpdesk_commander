# CI/CD ガイド

## 📋 概要

このプロジェクトでは GitHub Actions を使って CI を実行します。  
`main` への push と、`main` / `archetype/**` への PR で動作します。

**docs-only（`*.md` / `docs/*.md`）のみ変更の場合は CI をスキップ**します。

## 🔧 使用技術

- **CI/CDプラットフォーム**: GitHub Actions
- **Elixir**: 1.19.4
- **Erlang/OTP**: 28.3
- **PostgreSQL**: 16 (Alpine)
- **Assets**: `mix tailwind.install` / `mix esbuild.install` → `mix assets.deploy`

## 🎯 ワークフロー構成

### 1. Test Job

**目的**: コンパイルとテストの健全性を確認

**実行内容**:
- PostgreSQL 16 の起動（Service）
- `mix deps.get`
- `mix deps.compile`
- `mix compile --warnings-as-errors`
- `mix format --check-formatted`
- `mix test`

### 2. Quality Job

**目的**: Credo による品質チェック

**実行内容**:
- `mix deps.get`
- `mix credo --strict`

> **注意**: `prototype/* -> archetype/*` の PR では **quality/dialyzer/assets をスキップ**します。

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
- `mix tailwind.install --if-missing`
- `mix esbuild.install --if-missing`
- `mix assets.deploy`
- `priv/static/assets/js/app.js` / `css/app.css` の存在確認

> `SECRET_KEY_BASE` は CI で固定値を使用しています。

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
  ELIXIR_VERSION: "1.19.4"
  OTP_VERSION: "28.3"
```

### キャッシュ戦略

- **依存関係**: `deps/` と `_build/` を `mix.lock` でキャッシュ
- **Dialyzer PLT**: `priv/plts` を `mix.lock` でキャッシュ

## 🚀 ローカルでの実行

```bash
# まとめて実行（Dialyzer以外）
mix precommit

# CIと同等の個別実行
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
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
