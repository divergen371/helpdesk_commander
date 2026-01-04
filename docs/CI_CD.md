# CI/CD ガイド

## 📋 概要

このプロジェクトでは、GitHub Actionsを使用してCI/CDパイプラインを構築しています。
すべてのプッシュとプルリクエストに対して、自動的にテスト・コード品質チェック・型チェックが実行されます。

## 🔧 使用技術

- **CI/CDプラットフォーム**: GitHub Actions
- **Elixir**: 1.19.4
- **Erlang/OTP**: 28.3
- **PostgreSQL**: 16 (Alpine)
- **Node.js**: 20

## 🎯 ワークフロー構成

### 1. Test Job

**目的**: プロジェクトのテストを実行し、コードが正しく動作することを確認

**実行内容**:
- PostgreSQL 16のセットアップ (Docker サービス)
- 依存関係のインストール
- プロジェクトのコンパイル (`--warnings-as-errors`)
- フォーマットチェック (`mix format --check-formatted`)
- テストスイート実行 (`mix test`)

**トリガー**:
- `main`ブランチへのプッシュ
- プルリクエストの作成/更新

### 2. Quality Job

**目的**: Credoを使用してコード品質をチェック

**実行内容**:
- 依存関係のインストール
- Credoによる静的解析 (`mix credo --strict`)

**チェック項目**:
- コーディング規約
- コードの複雑度
- リファクタリング候補
- 潜在的なバグ

### 3. Dialyzer Job

**目的**: Dialyzerを使用して型エラーを検出

**実行内容**:
- 依存関係のインストール
- PLTキャッシュの復元/生成
- Dialyzer実行 (`mix dialyzer --format github`)

**チェック項目**:
- 型の不整合
- 到達不可能なコード
- 冗長なコード
- 仕様の不一致

### 4. Assets Job

**目的**: フロントエンドアセットのビルドが正常に完了することを確認

**実行内容**:
- Node.js 20のセットアップ
- Elixir/Node.js依存関係のインストール
- アセットのビルド (`mix assets.deploy`)
- ビルド成果物の検証 (app.js, app.css)

## 📊 ワークフロー詳細

### トリガー条件

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

- `main`ブランチへの直接プッシュ
- `main`ブランチへのプルリクエスト

### 環境変数

```yaml
env:
  MIX_ENV: test
  ELIXIR_VERSION: "1.19.4"
  OTP_VERSION: "28.3"
```

### キャッシュ戦略

**依存関係キャッシュ**:
```yaml
key: ${{ runner.os }}-mix-${{ matrix.elixir }}-${{ matrix.otp }}-${{ hashFiles('**/mix.lock') }}
```

**PLTキャッシュ** (Dialyzer用):
```yaml
key: ${{ runner.os }}-plt-${{ env.ELIXIR_VERSION }}-${{ env.OTP_VERSION }}-${{ hashFiles('**/mix.lock') }}
```

**アセットキャッシュ**:
```yaml
key: ${{ runner.os }}-mix-assets-${{ env.ELIXIR_VERSION }}-${{ env.OTP_VERSION }}-${{ hashFiles('**/mix.lock') }}-${{ hashFiles('**/package-lock.json') }}
```

## 🚀 使い方

### ローカルでCI相当のチェックを実行

プッシュ前に、ローカルでCIと同等のチェックを実行できます:

```bash
# すべてのチェックを実行
make precommit

# または個別に実行
mix format --check-formatted  # フォーマットチェック
mix compile --warnings-as-errors  # コンパイル
mix test  # テスト
mix credo --strict  # コード品質
mix dialyzer  # 型チェック
```

### GitHub Actionsの実行状況確認

1. GitHubリポジトリの「Actions」タブを開く
2. 実行中・完了したワークフローを確認
3. 失敗した場合は、該当ジョブをクリックして詳細を確認

### ワークフロー実行時間

**初回実行** (キャッシュなし):
- Test: 約5-7分
- Quality: 約3-5分
- Dialyzer: 約10-15分 (PLT生成)
- Assets: 約3-5分

**2回目以降** (キャッシュあり):
- Test: 約2-3分
- Quality: 約1-2分
- Dialyzer: 約2-3分
- Assets: 約1-2分

## 🔍 トラブルシューティング

### Test Jobが失敗する場合

**症状**: テストが失敗する

**確認事項**:
1. ローカルでテストが通るか確認: `mix test`
2. PostgreSQLが正しく起動しているか確認
3. データベース設定が正しいか確認 (`config/test.exs`)

**解決策**:
```bash
# ローカルでテスト
mix test

# 失敗したテストだけ再実行
mix test --failed
```

### Quality Jobが失敗する場合

**症状**: Credoの警告/エラー

**確認事項**:
```bash
# ローカルでCredoを実行
mix credo --strict

# 詳細を確認
mix credo --strict --verbose
```

**解決策**:
- Credoの警告に従ってコードを修正
- どうしても除外したい場合は`.credo.exs`で設定

### Dialyzer Jobが失敗する場合

**症状**: 型エラー

**確認事項**:
```bash
# ローカルでDialyzerを実行
mix dialyzer

# PLTを再生成
rm -rf priv/plts
mix dialyzer
```

**解決策**:
- 型の不整合を修正
- 誤検知の場合は`.dialyzer_ignore.exs`に追加

### Assets Jobが失敗する場合

**症状**: アセットのビルドエラー

**確認事項**:
```bash
# ローカルでアセットをビルド
npm install --prefix assets
mix assets.deploy
```

**解決策**:
- `package.json`の依存関係を確認
- `assets/`ディレクトリのエラーを修正

### キャッシュ関連の問題

**症状**: 依存関係が正しくインストールされない

**解決策**:
1. GitHubリポジトリの「Actions」→「Caches」からキャッシュを削除
2. ワークフローを再実行

または、ワークフローファイルでキャッシュキーを変更:
```yaml
key: v2-${{ runner.os }}-mix-...  # v1 -> v2 に変更
```

## 🛠 カスタマイズ

### Elixir/OTPバージョンの変更

`.github/workflows/ci.yml`を編集:

```yaml
env:
  ELIXIR_VERSION: "1.19.4"  # 変更
  OTP_VERSION: "28.3"       # 変更
```

### 複数バージョンでのテスト

マトリックス戦略を使用:

```yaml
strategy:
  matrix:
    elixir: ["1.18.4", "1.19.4"]
    otp: ["27.3", "28.3"]
```

### 新しいジョブの追加

例: セキュリティチェックジョブ

```yaml
security:
  name: Security Check
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ env.ELIXIR_VERSION }}
        otp-version: ${{ env.OTP_VERSION }}
    - run: mix deps.get
    - run: mix deps.audit
```

### ブランチ保護ルールの設定

GitHubリポジトリの設定で、`main`ブランチに保護ルールを追加:

1. Settings → Branches → Add rule
2. Branch name pattern: `main`
3. ☑ Require status checks to pass before merging
4. 必須チェックを選択:
   - Test
   - Code Quality
   - Dialyzer
   - Assets Build Check

## 📈 ステータスバッジ

READMEにステータスバッジを追加:

```markdown
[![CI](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml/badge.svg)](https://github.com/divergen371/helpdesk_commander/actions/workflows/ci.yml)
```

## 🎯 ベストプラクティス

### コミット前のチェック

```bash
# 必ずコミット前に実行
make precommit
```

### プルリクエストの作成

1. ローカルで`make precommit`を実行
2. すべてのチェックが通ることを確認
3. プルリクエストを作成
4. CI が緑色になるまで待つ

### 失敗したワークフローの対処

1. **まずローカルで再現**: CI で失敗したコマンドをローカルで実行
2. **ログを確認**: GitHub Actions のログを詳細に確認
3. **修正してプッシュ**: 修正をプッシュすると自動的に再実行される

### キャッシュの活用

- `mix.lock`を更新したら、最初のCI実行は時間がかかる
- 2回目以降は高速になる
- 問題があればキャッシュをクリア

## 📚 参考リンク

- [GitHub Actions ドキュメント](https://docs.github.com/ja/actions)
- [erlef/setup-beam](https://github.com/erlef/setup-beam)
- [actions/cache](https://github.com/actions/cache)
- [Elixir CI/CD ベストプラクティス](https://hexdocs.pm/phoenix/heroku.html)

## ✅ チェックリスト

### CI/CD構築時

- [x] `.github/workflows/ci.yml`を作成
- [x] Elixir/OTPバージョンを指定
- [x] PostgreSQLサービスを設定
- [x] キャッシュ戦略を設定
- [x] 全ジョブを定義 (test, quality, dialyzer, assets)

### プッシュ前

- [ ] `make precommit`を実行
- [ ] すべてのチェックがパス
- [ ] コミットメッセージを記述
- [ ] プッシュ

### プルリクエスト作成時

- [ ] CI が全て緑色
- [ ] コードレビューを依頼
- [ ] レビューコメントに対応
- [ ] マージ

## 🎉 まとめ

このCI/CDパイプラインにより、以下が自動化されます:

✅ **テストの自動実行** - バグの早期発見
✅ **コード品質チェック** - 一貫したコード品質
✅ **型チェック** - 型安全性の保証
✅ **アセットビルド** - フロントエンドの動作保証

これにより、安心してコードをプッシュでき、チーム全体でコード品質を維持できます。
