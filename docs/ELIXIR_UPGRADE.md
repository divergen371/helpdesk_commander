# Elixir 1.20.4 / Erlang OTP 29.1.2 アップグレード完了

## ✅ アップグレード結果

### バージョン情報

| コンポーネント | 旧バージョン | 新バージョン |
| --- | --- | --- |
| **Elixir** | 1.19.4 | **1.20.4** |
| **Erlang/OTP** | 28.3 | **29.1.2** |
| **PostgreSQL** | 18 | 18（変更なし） |

`.tool-versions` で以下を固定し、CI も同じバージョンに更新した。

```text
erlang 29.1.2
elixir ref:v1.20.4
```

### 実施内容

1. **ツールチェーンの更新**
   - `asdf install erlang 29.1.2`
   - `asdf install elixir ref:v1.20.4`
   - `.tool-versions` をリポジトリで管理（`.gitignore` から除外）

2. **依存関係の更新**
   - Ash 3.11.3 → **3.37.0**
   - AshPostgres 2.6.27 → **2.15.1**
   - AshPhoenix 2.3.18 → **2.3.25**
   - AshAuthentication 4.13.7 → **4.15.0**
   - Phoenix 1.8.3 → **1.8.16**
   - Phoenix LiveView 1.1.19 → **1.2.13**
   - LiveDashboard 0.8.7 → **0.9.1**
   - Ecto SQL 3.13.4 → **3.14.0**
   - Postgrex 0.21.1 → **0.22.4**
   - Swoosh 1.20.0 → **1.29.0**（セキュリティアドバイザリ解消）
   - その他、`mix deps.update` で解決された推移的依存

3. **Elixir 1.20 / Ash 3.37 対応**
   - `config :ash, default_string_length_count: :codepoints` を追加
     - Ash 3.37 では `min_length` / `max_length` 利用時に必須
   - `CurrentUser.id/1` を追加
     - `current_user && current_user.id` が Elixir 1.20 の型推論で警告になるため明示化
   - `<.button>` の `:rest` に `type` を追加
     - Phoenix LiveView 1.2 の属性検証で `type="button"` / `type="submit"` が警告になるため
   - `show/1,2` / `hide/1,2` の `@spec` を `map()` に変更
     - Phoenix LiveView 1.2 で `JS.t()` が opaque 型になり、Dialyzer が
       `contract_with_opaque` / `call_without_opaque` を報告するため

4. **動作確認**
   - `mix compile --force --warnings-as-errors`: 成功（プロジェクト側の警告 0）
   - `mix precommit`: 成功
   - `mix test`: **13 properties, 130 tests, 0 failures**
   - `mix credo --strict`: 指摘なし
   - `mix dialyzer`: **0 errors**
   - `MIX_ENV=test mix coveralls`: **80.5%**（基準 80% を満たす）

## ⚠️ 互換性・移行時の注意

### 1. Ash 3.37 の文字列長カウント

`config :ash, default_string_length_count: :codepoints` を設定しないと、
Ash リソースのコンパイル時に `Spark.Error.DslError` が発生する。

`:codepoints` は PostgreSQL の文字数カウントと一致するため、DB 側の制約と
アプリ側バリデーションの齟齬を避けられる。

### 2. Elixir 1.20 の型推論警告

Elixir 1.20 では型推論が強化され、従来は警告にならなかった
「常に真/偽になる条件」が `--warnings-as-errors` で失敗する。

今回の対応:

- nil 許容の値を `&&` で分岐していた箇所を `CurrentUser.id/1` に集約
- HEEx コンポーネントの未宣言属性を `attr :rest, :global, include: [...]` に追加

### 3. rebar3 のグローバルプラグイン

OTP 29 では、グローバルに導入した古い `rebar3_format`（依存の `katana_code`）が
`catch` の deprecation 警告を `warnings_as_errors` で失敗させ、依存コンパイルが
巻き添えで失敗することがある。

CI やクリーンな環境では発生しない。ローカルで発生する場合は、次のいずれかを行う。

```bash
# 1. プロジェクト用にクリーンなグローバル設定ディレクトリを使う
export REBAR_GLOBAL_CONFIG_DIR=/tmp/rebar-clean
mkdir -p "$REBAR_GLOBAL_CONFIG_DIR/.config/rebar3"

# 2. 不要な場合はグローバルプラグインを外す
# ~/.config/rebar3/rebar.config の {plugins, [rebar3_format]}. を削除
```

## 🔧 今後の推奨事項

- `mix hex.outdated` で依存更新を定期的に確認する
- `mix precommit` と `mix coveralls` をローカルでも実行する
- カバレッジは 80.5% のため、新規コードにはテストを同時に追加する
- `docs/ELIXIR_UPGRADE.md`（本ドキュメント）と `docs/STATUS.md` を更新する

## 📋 アップグレードチェックリスト

- [x] Erlang/OTP 29.1.2 インストール
- [x] Elixir ref:v1.20.4 インストール
- [x] `.tool-versions` のリポジトリ管理
- [x] 依存関係の更新
- [x] Ash 3.37 の必須設定追加
- [x] Elixir 1.20 の型警告修正
- [x] `mix dialyzer` 0 errors
- [x] `mix precommit` 成功
- [x] テスト成功（13 properties / 130 tests）
- [x] カバレッジ 80% 以上
- [x] CI のバージョン更新
- [ ] 本番環境への反映計画
- [ ] チーム全体への周知

## 📚 参考リンク

- [Elixir 1.20 Release Notes](https://github.com/elixir-lang/elixir/releases/tag/v1.20.0)
- [Erlang/OTP 29 Release Notes](https://www.erlang.org/downloads/29)
- [Ash 3.x Changelog](https://github.com/ash-project/ash/blob/main/CHANGELOG.md)
- [Upgrading Elixir Guide](https://hexdocs.pm/elixir/compatibility-and-deprecations.html)

## ✅ 結論

Erlang/OTP 29.1.2 + Elixir 1.20.4 へのアップグレードは成功した。
`mix precommit`、テスト、Credo、カバレッジのすべてが基準を満たしている。
