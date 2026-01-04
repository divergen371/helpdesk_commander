defmodule HelpdeskCommander.Repo do
  use AshPostgres.Repo,
    otp_app: :helpdesk_commander

  # マルチテナント（スキーマベース）を使っていない場合でも、AshPostgres.Repo が提供する
  # デフォルト実装は raise するため Dialyzer の :no_return 警告になります。
  # 必要になったら、ここを実際の tenant schema 一覧（例: org.schema）に置き換えてください。
  @impl AshPostgres.Repo
  @spec all_tenants() :: [String.t()]
  def all_tenants, do: []

  @impl AshPostgres.Repo
  @spec installed_extensions() :: [String.t() | module()]
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions"]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl AshPostgres.Repo
  @spec prefer_transaction?() :: false
  def prefer_transaction? do
    false
  end

  @impl AshPostgres.Repo
  @spec min_pg_version() :: Version.t()
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
