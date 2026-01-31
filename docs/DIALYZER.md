# Dialyzer 使い方ガイド

## 📋 概要

Dialyzer（Dialyxir）は、Elixirの**静的型チェックツール**です。実行時エラーになる可能性のある型の不一致を事前に検出します。

## 🎯 Dialyzerの役割

### Credoとの違い

| ツール | 役割 | チェック内容 |
|--------|------|------------|
| **Credo** | コードスタイル・品質 | 命名規則、構造、ベストプラクティス |
| **Dialyzer** | 型の整合性 | 型エラー、関数の戻り値、パターンマッチ |

両方を組み合わせることで、より堅牢なコードになります。

## 🚀 基本的な使い方

### 初回セットアップ（PLT生成）

```bash
# PLTファイルを生成（初回のみ、10-15分かかる）
make dialyzer-plt

# または
mix dialyzer --plt
```

**PLT**（Persistent Lookup Table）は、標準ライブラリと依存関係の型情報をキャッシュしたファイルです。

### 型チェックを実行

```bash
# 通常の実行
make dialyzer

# または
mix dialyzer
```

### PLTの更新

依存関係を追加・更新したら：

```bash
make dialyzer-plt
```

## 📊 検出できる問題

### 1. 型の不一致

```elixir
# 問題のあるコード
@spec add(integer(), integer()) :: integer()
def add(a, b) do
  "#{a + b}"  # 文字列を返している！
end

# Dialyzerの警告:
# The @spec return type does not match the actual return type.
```

### 2. 存在しない関数の呼び出し

```elixir
# 問題のあるコード
def process_user(user) do
  user.non_existent_field()  # このメソッドは存在しない
end

# Dialyzerの警告:
# Function non_existent_field/1 undefined
```

### 3. パターンマッチの不整合

```elixir
# 問題のあるコード
def handle_result({:ok, value}) do
  value
end

def call_function do
  result = {:error, "failed"}
  handle_result(result)  # {:error, ...}は処理できない
end

# Dialyzerの警告:
# The pattern {:ok, _} can never match
```

### 4. 到達不可能なコード

```elixir
# 問題のあるコード
def check_number(n) when is_integer(n) do
  if n > 0 do
    :positive
  else
    :negative_or_zero
  end
  
  :unreachable  # ここには到達しない
end

# Dialyzerの警告:
# Expression produces a value that is never used
```

## 🔧 プロジェクトの設定

### mix.exs設定

```elixir
defp dialyzer do
  [
    # PLTファイルの保存場所
    plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
    
    # 追加でチェックするアプリケーション
    plt_add_apps: [:ex_unit, :mix],
    
    # チェックフラグ
    flags: [
      :error_handling,      # エラーハンドリングの問題
      :underspecs,          # 型仕様が不十分
      :unknown,             # 未知の関数・型
      :unmatched_returns    # 使われていない戻り値
    ],
    
    # 無視するファイル
    ignore_warnings: ".dialyzer_ignore.exs",
    
    # 未使用のフィルタをリスト表示
    list_unused_filters: true
  ]
end
```

### 警告の無視設定（`.dialyzer_ignore.exs`）

```elixir
[
  # Phoenix生成コードの既知の問題を無視
  ~r"lib/helpdesk_commander_web.ex",
  
  # テストヘルパーの警告を無視
  ~r"test/support/"
]
```

## 💡 @specの書き方

### 基本的な型仕様

```elixir
# 単純な関数
@spec add(integer(), integer()) :: integer()
def add(a, b), do: a + b

# 複数の戻り値パターン
@spec divide(number(), number()) :: {:ok, float()} | {:error, String.t()}
def divide(a, 0), do: {:error, "Division by zero"}
def divide(a, b), do: {:ok, a / b}

# リストとマップ
@spec process_users([User.t()]) :: map()
def process_users(users) do
  # ...
end

# nilを許容
@spec find_user(integer()) :: User.t() | nil
def find_user(id) do
  # ...
end
```

### Ash/Ecto用の型仕様

```elixir
# Ashリソース
@spec create_task(map()) :: {:ok, Task.t()} | {:error, Ash.Error.t()}
def create_task(attrs) do
  Task.create(attrs)
end

# Ectoクエリ
@spec list_tasks() :: [Task.t()]
def list_tasks do
  Repo.all(Task)
end

# Ecto Changeset
@spec validate_task(Task.t(), map()) :: Ecto.Changeset.t()
def validate_task(task, attrs) do
  task
  |> cast(attrs, [:title, :description])
  |> validate_required([:title])
end
```

### LiveView用の型仕様

```elixir
@spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
def mount(_params, _session, socket) do
  {:ok, assign(socket, :tasks, [])}
end

@spec handle_event(String.t(), map(), Socket.t()) ::
        {:noreply, Socket.t()} | {:reply, map(), Socket.t()}
def handle_event("save", %{"task" => task_params}, socket) do
  # ...
end
```

## 🎯 ベストプラクティス

### 1. 段階的に導入

```bash
# まずは特定のモジュールだけチェック
mix dialyzer lib/helpdesk_commander/tasks/task.ex

# 問題なければ全体に適用
mix dialyzer
```

### 2. 公開関数には必ず@specを追加

```elixir
# ✅ 良い例
@spec create_user(map()) :: {:ok, User.t()} | {:error, term()}
def create_user(attrs) do
  # ...
end

# ❌ 避ける（privateは任意）
defp internal_helper(data) do
  # @specは任意
end
```

### 3. CI/CDに統合

```yaml
# .github/workflows/ci.yml
- name: Cache PLT
  uses: actions/cache@v4
  with:
    path: priv/plts
    key: ${{ runner.os }}-plt-${{ env.ELIXIR_VERSION }}-${{ env.OTP_VERSION }}-${{ hashFiles('**/mix.lock') }}

- name: Run Dialyzer
  run: |
    mix dialyzer --format github || (rm -f priv/plts/dialyzer.plt priv/plts/dialyzer.plt.hash && mix dialyzer --plt && mix dialyzer --format github)
```

### 4. 定期的にPLTを更新

```bash
# 依存関係を更新したら
mix deps.update --all
make dialyzer-plt
```

## 🔍 よくあるエラーと対処法

### 1. "The @spec return type does not match"

**問題**: 関数の実際の戻り値が@specと一致しない

**対処法**:

```elixir
# 修正前
@spec get_user(integer()) :: User.t()
def get_user(id) do
  case Repo.get(User, id) do
    nil -> nil        # User.t()ではなくnil
    user -> user
  end
end

# 修正後
@spec get_user(integer()) :: User.t() | nil
def get_user(id) do
  Repo.get(User, id)
end
```

### 2. "Function clause will never match"

**問題**: パターンマッチが常に失敗する

**対処法**:

```elixir
# 修正前
def handle_result({:ok, value}), do: value
def handle_result(:error), do: nil  # {:error, _}とマッチしない

# 修正後
def handle_result({:ok, value}), do: value
def handle_result({:error, _reason}), do: nil
```

### 3. "Unknown function"

**問題**: Dialyzerが関数を見つけられない

**対処法**:

```elixir
# PLTに追加
# mix.exs
defp dialyzer do
  [
    plt_add_apps: [:ex_unit, :mix, :missing_app]
  ]
end
```

### 4. PLT生成が失敗する

```bash
# PLTファイルとハッシュを削除して再生成
rm -f priv/plts/dialyzer.plt priv/plts/dialyzer.plt.hash
make dialyzer-plt
```

### 5. `repo.ex` で `no_return`（`all_tenants/0`）が出る

**症状**（例）:

- `lib/helpdesk_commander/repo.ex:2:no_return`
- `Function all_tenants/0 only terminates with explicit exception.`

**原因**:

`HelpdeskCommander.Repo` は `use AshPostgres.Repo` を使っています。
AshPostgres 側は schema-based multitenancy 用に `all_tenants/0` のコールバックを持っていて、
未実装の場合は **デフォルト実装が `raise` する**ため、Dialyzer では `no_return` 扱いになります。

**対処（今回の対応）**:

`lib/helpdesk_commander/repo.ex` に `all_tenants/0` を明示的に実装して、例外終了しないようにしました。
現時点では schema-based multitenancy を使っていない前提で `[]` を返しています。

また、この警告を一時的に抑えるために置いていた `.dialyzer_ignore.exs` のフィルタは不要になったため削除しました。

#### 将来的に schema-based multitenancy を使う場合の注意点

`all_tenants/0` を `[]` のままにすると、AshPostgres のタスクやマイグレーション（特に tenants 対応）で
「テナント一覧が空」として扱われ、期待通りに動かない可能性があります。

schema-based multitenancy を使うことになったら、次を満たす実装に差し替えてください:

- **全テナントのスキーマ名（prefix）** を `String.t()` のリストで返す
- テナントが増減しても正しく追従できる（例: DB から organizations を取得して `org.schema` を返す、など）
- テナントマイグレーションを回す運用をするなら、テナントのマイグレーションパスや実行手順も合わせて整備する

（参考: AshPostgres 側で `repo.all_tenants()` を使って tenant migration を走らせる箇所があります）

## 📈 推奨ワークフロー

### 開発中

```bash
# 1. コードを書く
# 2. @specを追加
# 3. 型チェック
make dialyzer

# 4. 問題があれば修正
# 5. コミット
```

### 新しいモジュール作成時

```bash
# モジュール作成
# ↓
# 公開関数に@specを追加
# ↓
mix dialyzer lib/my_new_module.ex
```

### コミット前

```bash
# 全チェックを実行
mix precommit  # Credo + テストも含む
make dialyzer  # Dialyzerは別途実行
```

## ⚡ パフォーマンス最適化

### PLTのキャッシュ

```bash
# チーム共有のPLTを使用（オプション）
export DIALYZER_PLT=/shared/team/dialyzer.plt
```

### 並列実行

```elixir
# mix.exs
defp dialyzer do
  [
    plt_parallel: true  # 並列でPLT生成
  ]
end
```

## 🐛 トラブルシューティング

### Dialyzerが遅い

```bash
# 1. PLTを削除して再生成
rm -rf priv/plts/
make dialyzer-plt

# 2. 並列実行を有効化（mix.exs）
plt_parallel: true
```

### 誤検知が多い

```elixir
# .dialyzer_ignore.exsに追加
[
  ~r"lib/generated_code/",
  ~r"specific_file.ex:123"  # 特定の行を無視
]
```

### PLTが見つからない

```bash
# ディレクトリを作成
mkdir -p priv/plts

# PLTを生成
make dialyzer-plt
```

## 📚 参考リンク

- [Dialyxir公式ドキュメント](https://hexdocs.pm/dialyxir/)
- [Elixir型仕様](https://hexdocs.pm/elixir/typespecs.html)
- [Erlang Dialyzer](https://www.erlang.org/doc/man/dialyzer.html)

## 📊 チェックリスト

- [ ] Dialyxir依存関係追加
- [ ] mix.exsに設定追加
- [ ] PLTファイル生成
- [ ] 公開関数に@spec追加
- [ ] Dialyzer実行して問題修正
- [ ] CI/CDに統合
- [ ] チーム全体で使用開始
