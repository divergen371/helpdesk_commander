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
