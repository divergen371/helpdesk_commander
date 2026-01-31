# コード品質ツール統合ガイド

このプロジェクトでは、3つのコード品質ツールを使用しています。

## 🛠 ツール一覧

| ツール | 役割 | 実行コマンド |
|--------|------|------------|
| **Formatter** | コードフォーマット | `make format` |
| **Credo** | コードスタイル・品質 | `make credo` |
| **Dialyzer** | 静的型チェック | `make dialyzer` |

## 📊 各ツールの役割

### 1. Formatter（組み込み）

**役割**: コードの一貫したフォーマット

**チェック内容**:
- インデント
- スペーシング
- 改行位置
- 行の長さ（120文字）
- トレーリングカンマ
- import/aliasのソート

**実行**:
```bash
make format              # フォーマット実行
mix format --check-formatted  # チェックのみ
```

詳細: [docs/FORMATTER.md](./FORMATTER.md)

### 2. Credo

**役割**: コードの品質とベストプラクティス

**チェック内容**:
- 命名規則
- コードの複雑度
- 可読性
- 設計パターン

**実行**:
```bash
make credo         # 通常モード
make credo-strict  # 厳格モード
```

詳細: [docs/CREDO.md](./CREDO.md)

### 3. Dialyzer

**役割**: 型の整合性チェック

**チェック内容**:
- 型エラー
- パターンマッチの不整合
- 未使用の戻り値
- 到達不可能なコード

**実行**:
```bash
make dialyzer-plt  # 初回のみ（10-15分）
make dialyzer      # 型チェック実行
```

詳細: [docs/DIALYZER.md](./DIALYZER.md)

## 🚀 推奨ワークフロー

### 開発中

```bash
# 1. コードを書く
vim lib/my_module.ex

# 2. フォーマット
make format

# 3. コード品質チェック
make credo

# 4. テスト
make test
```

### コミット前

```bash
# 全チェックを実行
mix precommit

# 以下が実行されます:
# - コンパイル（警告→エラー）
# - 未使用依存関係チェック
# - フォーマット
# - Credo（厳格モード）
# - テスト
```

### マージ前（推奨）

```bash
# 型チェックも追加
make dialyzer
```

## 📋 チェックリスト

### 新しいモジュール作成時

- [ ] 公開関数に`@spec`を追加
- [ ] `@moduledoc`を追加
- [ ] フォーマット実行
- [ ] Credoでチェック
- [ ] Dialyzerでチェック
- [ ] テストを書く

### プルリクエスト前

- [ ] `mix precommit`が成功
- [ ] `make dialyzer`が成功
- [ ] テストカバレッジが十分
- [ ] ドキュメントが更新されている

## 🔧 設定ファイル

| ファイル | 用途 |
|---------|------|
| `.formatter.exs` | Formatter設定 |
| `.credo.exs` | Credo設定 |
| `.dialyzer_ignore.exs` | Dialyzer警告の無視設定 |
| `mix.exs` | 全ツールの統合設定 |

## 💡 ヒント

### 警告レベルの調整

プロジェクトの成熟度に応じて調整:

**初期段階**:
- Formatter: 必須
- Credo: 警告のみ
- Dialyzer: オプション

**成熟段階**:
- Formatter: 必須
- Credo: エラーとして扱う
- Dialyzer: 必須

### CI/CDでの実行順序

現在の CI はジョブ分割されています（`docs/CI_CD.md`参照）。

```text
Test Job:
  - mix deps.get
  - mix deps.compile
  - mix compile --warnings-as-errors
  - mix format --check-formatted
  - mix test

Quality Job:
  - mix credo --strict

Dialyzer Job:
  - mix dialyzer --format github

Assets Job:
  - mix assets.deploy
```

## 🐛 トラブルシューティング

### すべてのチェックを一度に修正しようとしない

```bash
# 段階的に修正
make format      # まずフォーマット
make credo       # 次にCredo
make dialyzer    # 最後にDialyzer
```

### Credoの警告が多すぎる

`.credo.exs`で特定のチェックを無効化または緩和

### Dialyzerが遅い

PLTをキャッシュ（CI/CD環境）

## 📚 参考資料

- [Credo使い方ガイド](./CREDO.md)
- [Dialyzer使い方ガイド](./DIALYZER.md)
- [Elixir Formatter](https://hexdocs.pm/mix/Mix.Tasks.Format.html)
