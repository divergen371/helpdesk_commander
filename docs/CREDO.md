# Credo 使い方ガイド

## 📋 概要

Credoは、Elixirの静的コード解析ツールです。コードの品質、一貫性、ベストプラクティスへの準拠をチェックします。

## 🚀 基本的な使い方

### 通常モードで実行

```bash
mix credo

# または
make credo
```

### 厳格モードで実行（推奨）

```bash
mix credo --strict

# または
make credo-strict
```

### 特定のファイルのみチェック

```bash
mix credo lib/helpdesk_commander/tasks/task.ex
```

### 問題の詳細を確認

```bash
mix credo explain lib/helpdesk_commander_web.ex:1:11
```

## 📊 チェックのカテゴリ

### 1. Consistency（一貫性）

コード全体で一貫したスタイルを保つためのチェック。

```elixir
# 良い例: 一貫した命名
def create_user(params), do: ...
def update_user(id, params), do: ...
def delete_user(id), do: ...

# 悪い例: 一貫性がない
def createUser(params), do: ...
def user_update(id, params), do: ...
def removeUser(id), do: ...
```

### 2. Design（設計）

より良い設計パターンを推奨するチェック。

```elixir
# 良い例: 適切なモジュール設計
defmodule Tasks do
  alias Tasks.{Task, User}  # ネストが浅い
end

# 悪い例: 過度にネストされたエイリアス
defmodule Tasks do
  alias Tasks.Domain.Context.Module.SubModule.Task
end
```

### 3. Readability（可読性）

コードの読みやすさを向上させるチェック。

```elixir
# 良い例: 適切な関数名
def valid_email?(email), do: ...

# 悪い例: 述語関数なのに?がない
def is_valid_email(email), do: ...
```

### 4. Refactoring（リファクタリング）

コードの改善機会を指摘するチェック。

```elixir
# 良い例: シンプルな条件
if user.active?, do: send_email(user)

# 悪い例: 不要な複雑さ
unless !user.active?, do: send_email(user)
```

### 5. Warning（警告）

潜在的なバグやセキュリティ問題を警告。

```elixir
# 良い例: 安全なアトム変換
def to_atom(string) when is_atom(string), do: string
def to_atom(string), do: String.to_existing_atom(string)

# 悪い例: メモリリークの可能性
def to_atom(string), do: String.to_atom(string)  # 危険！
```

## 🔧 プロジェクトの設定

### 現在の設定（`.credo.exs`）

```elixir
%{
  configs: [
    %{
      name: "default",
      strict: true,  # 厳格モード有効
      checks: %{
        enabled: [
          # 主要なチェック項目
          {Credo.Check.Readability.MaxLineLength, [max_length: 120]},
          {Credo.Check.Refactor.ModuleDependencies, [max_deps: 20]},
          {Credo.Check.Readability.Specs, [include_defp: false]},
          # ...その他多数
        ]
      }
    }
  ]
}
```

### カスタマイズ方法

特定のチェックを無効にする場合：

```elixir
checks: %{
  disabled: [
    {Credo.Check.Readability.ModuleDoc, []}
  ]
}
```

特定のファイルを除外する場合：

```elixir
files: %{
  excluded: [
    ~r"/_build/",
    ~r"/deps/",
    ~r"/generated_files/"
  ]
}
```

## 💡 よくある問題と対処法

### 1. "Functions should have a @spec type specification"

**問題**: 関数に型仕様がない

**対処法**:

```elixir
# 修正前
def create_task(attrs) do
  # ...
end

# 修正後
@spec create_task(map()) :: {:ok, Task.t()} | {:error, term()}
def create_task(attrs) do
  # ...
end
```

### 2. "Module has too many dependencies"

**問題**: モジュールが多くの依存関係を持っている

**対処法**: モジュールを分割するか、依存関係の上限を調整

```elixir
# .credo.exsで調整
{Credo.Check.Refactor.ModuleDependencies, [max_deps: 20]}
```

### 3. "Unused variables should be named consistently"

**問題**: 未使用変数の命名が一貫していない

**対処法**:

```elixir
# 修正前
def handle_event("save", params, socket) do
  _unused = something()
  {something_else, _} = other()
end

# 修正後（全て_prefixを統一）
def handle_event("save", params, socket) do
  _result = something()
  {something_else, _value} = other()
end
```

## 🔄 CI/CDへの統合

### GitHub Actions例

```yaml
- name: Run Credo
  run: mix credo --strict --format=json
```

### プリコミットフックとして使用

`precommit`エイリアスに含まれています：

```bash
mix precommit
```

以下が実行されます：
1. コンパイル（警告をエラーとして扱う）
2. 未使用依存関係のチェック
3. コードフォーマット
4. **Credo（厳格モード）**
5. テスト実行

## 📈 推奨ワークフロー

### 開発中

```bash
# コードを書く
# ↓
make format      # フォーマット
# ↓
make credo       # Credoチェック
# ↓
make test        # テスト実行
```

### コミット前

```bash
mix precommit    # 全チェックを実行
```

### マージ前

```bash
make credo-strict  # 厳格モードで最終チェック
```

## 🎯 ベストプラクティス

### 1. 段階的に導入

最初は警告レベルを低く設定し、徐々に厳格化：

```bash
# まずは警告のみ表示
mix credo --format=oneline

# 慣れてきたら厳格モード
mix credo --strict
```

### 2. チーム全体で設定を共有

`.credo.exs`をバージョン管理に含める（済み✅）

### 3. 定期的に実行

- プルリクエスト時
- CI/CDパイプライン
- ローカル開発時

### 4. 問題を理解してから修正

```bash
# 問題の詳細を確認
mix credo explain lib/my_file.ex:10:5

# 理解してから修正
```

## 📚 参考リンク

- [Credo公式ドキュメント](https://hexdocs.pm/credo/)
- [チェック一覧](https://hexdocs.pm/credo/check_params.html)
- [設定ファイルガイド](https://hexdocs.pm/credo/config_file.html)

## 🛠 トラブルシューティング

### Credoが遅い

```bash
# キャッシュをクリア
mix clean
mix credo
```

### 特定のチェックを一時的に無効化

```elixir
# コード内でインラインで無効化
# credo:disable-for-next-line Credo.Check.Readability.Specs
def my_function do
  # ...
end
```

### 既存コードで大量の警告

```bash
# まずは新しいコードのみチェック
git diff --name-only | xargs mix credo --files-included
```
