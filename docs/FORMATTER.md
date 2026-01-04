# Elixir Formatter 設定ガイド

## 📋 概要

`.formatter.exs`は、Elixirの組み込みコードフォーマッターの設定ファイルです。
チーム全体で一貫したコードスタイルを自動的に維持します。

## 🔧 現在の設定

### 完全な設定内容

```elixir
# .formatter.exs
[
  # フォーマット対象のファイル
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "priv/*/seeds.exs"
  ],
  
  # マイグレーションファイルも個別にフォーマット
  subdirectories: ["priv/*/migrations"],
  
  # 依存ライブラリからフォーマット設定をインポート
  import_deps: [:ash, :ash_phoenix, :ash_postgres, :ecto, :ecto_sql, :phoenix],
  
  # LiveViewのHTMLフォーマッター
  plugins: [Phoenix.LiveView.HTMLFormatter],
  
  # 行の長さ制限（Credoと統一）
  line_length: 120,
  
  # トレーリングカンマ（複数行の場合）
  trailing_comma: true,
  
  # インポート/エイリアスのソート
  import_deps_sort: :by_first_use
]
```

## 📊 各設定項目の解説

### 1. inputs

**役割**: フォーマット対象のファイルパターンを指定

```elixir
inputs: [
  "*.{heex,ex,exs}",                      # ルートディレクトリの.ex, .exs, .heexファイル
  "{config,lib,test}/**/*.{heex,ex,exs}", # config, lib, test内の全ファイル
  "priv/*/seeds.exs"                      # シードファイル
]
```

**含まれるファイル**:
- `mix.exs`
- `config/config.exs`, `config/dev.exs` など
- `lib/**/*.ex`
- `test/**/*.exs`
- `lib/**/*.html.heex` (LiveViewテンプレート)
- `priv/repo/seeds.exs`

### 2. subdirectories

**役割**: 独立してフォーマットするサブディレクトリ

```elixir
subdirectories: ["priv/*/migrations"]
```

**理由**: マイグレーションファイルは独自の`.formatter.exs`を持つことが多いため、個別に処理します。

### 3. import_deps

**役割**: 依存ライブラリのフォーマットルールをインポート

```elixir
import_deps: [:ash, :ash_phoenix, :ash_postgres, :ecto, :ecto_sql, :phoenix]
```

**効果**:
- Ashのマクロ（`attributes`, `actions`など）が正しくフォーマットされる
- Ectoのクエリが適切にインデントされる
- Phoenix固有の構文が認識される

### 4. plugins

**役割**: 追加のフォーマッタープラグイン

```elixir
plugins: [Phoenix.LiveView.HTMLFormatter]
```

**効果**:
- `.heex`ファイルのHTMLが整形される
- HEEx構文（`<%= %>`、`{@assign}`など）が正しくフォーマットされる

**フォーマット例**:

```heex
# Before
<div class="flex"><span>{@user.name}</span><button phx-click="delete">Delete</button></div>

# After
<div class="flex">
  <span>{@user.name}</span>
  <button phx-click="delete">Delete</button>
</div>
```

### 5. line_length

**役割**: 1行の最大文字数

```elixir
line_length: 120
```

**理由**:
- Credoの設定（120文字）と統一
- 現代のワイドモニターで読みやすい
- コードレビューツールでも見やすい

**効果**:

```elixir
# 120文字を超える場合、自動的に改行される
def very_long_function_name_with_many_parameters(
      first_param,
      second_param,
      third_param,
      fourth_param
    ) do
  # ...
end
```

### 6. trailing_comma

**役割**: 複数行のリスト/マップで末尾カンマを追加

```elixir
trailing_comma: true
```

**効果**:

```elixir
# trailing_comma: true
users = [
  %{name: "Alice", age: 30},
  %{name: "Bob", age: 25},
  %{name: "Carol", age: 35},  # ← カンマが追加される
]

# trailing_comma: false
users = [
  %{name: "Alice", age: 30},
  %{name: "Bob", age: 25},
  %{name: "Carol", age: 35}   # ← カンマなし
]
```

**メリット**:
- Gitの差分が綺麗になる（新しい要素を追加しても前の行が変更されない）
- 要素の並び替えが簡単

### 7. import_deps_sort

**役割**: import/alias/use文のソート方法

```elixir
import_deps_sort: :by_first_use
```

**オプション**:
- `:by_first_use` - 最初に使われた順（推奨）
- `:alphabetical` - アルファベット順
- `:none` - ソートしない

**効果**:

```elixir
# :by_first_use
defmodule MyModule do
  alias MyApp.Users.User      # Userを先に使う
  alias MyApp.Posts.Post      # その後Postを使う
  
  def get_user_posts(%User{} = user) do
    Post.for_user(user)
  end
end
```

## 🚀 使い方

### 基本コマンド

```bash
# すべてのファイルをフォーマット
mix format

# または
make format
```

### フォーマットチェック（CI用）

```bash
# フォーマットされているか確認（変更しない）
mix format --check-formatted
```

CI/CDで使用：

```yaml
# .github/workflows/ci.yml
- name: Check formatting
  run: mix format --check-formatted
```

### 特定のファイルのみフォーマット

```bash
# 1つのファイル
mix format lib/my_module.ex

# 複数のファイル
mix format lib/module1.ex lib/module2.ex

# ディレクトリ
mix format lib/my_app/**/*.ex
```

### エディタ統合

#### VS Code

```json
// settings.json
{
  "elixir.formatOnSave": true,
  "editor.formatOnSave": true
}
```

#### Vim/Neovim

```vim
" 保存時に自動フォーマット
autocmd BufWritePre *.ex,*.exs :!mix format %
```

## 💡 ベストプラクティス

### 1. コミット前に必ずフォーマット

```bash
# Git hook（.git/hooks/pre-commit）
#!/bin/sh
mix format --check-formatted || {
  echo "Code is not formatted. Run 'mix format'"
  exit 1
}
```

または`precommit`エイリアスを使用：

```bash
mix precommit  # フォーマット + Credo + テスト
```

### 2. フォーマット設定をチーム全体で共有

- `.formatter.exs`をバージョン管理に含める（✅済み）
- チーム全員が同じElixirバージョンを使用

### 3. フォーマットの一貫性を保つ

```bash
# 新しい依存関係を追加したら
mix deps.get
mix format  # 依存関係の設定を反映
```

## 🔍 よくある質問

### Q1: フォーマッターが変更しない箇所がある

**A**: 一部の構文は意図的に保持されます：

```elixir
# ブロックの改行は保持される
def function do
  # 空行も保持
  
  result
end

# 意図的な整列も保持される（ある程度）
x     = 1
long  = 2
value = 3
```

### Q2: 特定のコードをフォーマットから除外したい

**A**: コメントで無効化：

```elixir
# Code.format_string! skip: true
def unformatted_code do
  x=1+2  # フォーマットされない
end
```

ただし、**推奨しません**。フォーマッターに従うのがベストプラクティスです。

### Q3: 行の長さが120文字を超えてしまう

**A**: フォーマッターは可能な限り改行しますが、以下の場合は超える可能性があります：

- 文字列リテラルが長い
- 長いアトムや関数名

```elixir
# これは仕方ない
error_message = "This is a very long error message that cannot be split across multiple lines without breaking the string"

# こうできる
error_message =
  "This is a very long error message " <>
  "that is now split across multiple lines"
```

## 📊 フォーマット前後の比較

### Before

```elixir
defmodule MyModule do
use GenServer
alias MyApp.{User,Post,Comment}
def start_link(opts),do: GenServer.start_link(__MODULE__,opts,name: __MODULE__)
def init(state),do: {:ok,state}
def handle_call({:get,id},_from,state) do
user=Enum.find(state.users,fn u -> u.id==id end)
{:reply,user,state}
end
end
```

### After

```elixir
defmodule MyModule do
  use GenServer

  alias MyApp.Comment
  alias MyApp.Post
  alias MyApp.User

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(state), do: {:ok, state}

  def handle_call({:get, id}, _from, state) do
    user = Enum.find(state.users, fn u -> u.id == id end)
    {:reply, user, state}
  end
end
```

## 🎯 まとめ

### メリット

✅ コードレビューの時間短縮（スタイルの議論が不要）
✅ 一貫性のあるコードベース
✅ 新メンバーのオンボーディング容易
✅ Gitの差分が読みやすい
✅ 自動化可能

### チーム全体で守るべきルール

1. **常にフォーマットしてからコミット**
2. **`.formatter.exs`は編集しない**（チームで合意なしに）
3. **エディタの自動フォーマット機能を有効化**

## 📚 参考リンク

- [Elixir Formatter公式ドキュメント](https://hexdocs.pm/mix/Mix.Tasks.Format.html)
- [Phoenix.LiveView.HTMLFormatter](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.HTMLFormatter.html)
- [コードスタイルガイド](https://github.com/christopheradams/elixir_style_guide)
