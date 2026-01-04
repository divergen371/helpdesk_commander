[
  # 以前は AshPostgres.Repo のデフォルト all_tenants/0 が raise するため
  # Dialyzer の :no_return をここで握りつぶしていました。
  # 現在は HelpdeskCommander.Repo 側で all_tenants/0 を実装したので不要です。
]
