defmodule HelpdeskCommander.SSO do
  @moduledoc """
  社内 IdP との SSO 接続（OIDC）の設定とユーザーマッピング。

  - 方式: OIDC（Authorization Code Flow、state/nonce 検証）
  - 連携ライブラリ: Assent（`Assent.Strategy.OIDC`）
  - 会社は SSO_COMPANY_CODE（または /auth/sso/start/:company_code）で決める
  - ロールは SSO_ROLE_CLAIM（既定 groups）の中に SSO_ADMIN_GROUP があれば admin、
    なければ user
  """

  @doc "SSO 設定全体（Application 環境 :helpdesk_commander, :sso）。"
  @spec config() :: keyword()
  def config do
    Application.get_env(:helpdesk_commander, :sso, [])
  end

  @spec enabled?() :: boolean()
  def enabled? do
    config(:enabled, false) and is_binary(config(:base_url)) and
      is_binary(config(:client_id)) and is_binary(config(:client_secret))
  end

  @spec config(atom(), term()) :: term()
  def config(key, default \\ nil) do
    :helpdesk_commander
    |> Application.get_env(:sso, [])
    |> Keyword.get(key, default)
  end

  @spec default_company_code() :: String.t()
  def default_company_code do
    config(:company_code) || HelpdeskCommander.Accounts.Auth.default_company_code()
  end

  @doc """
  IdP の claims からロールを決める。`SSO_ROLE_CLAIM`（既定 groups）をリストで読み、
  `SSO_ADMIN_GROUP` と一致する項目があれば admin。
  """
  @spec resolve_role(map()) :: String.t()
  def resolve_role(claims) when is_map(claims) do
    claim_key = config(:role_claim, "groups")
    admin_group = config(:admin_group)

    assigned =
      claims
      |> Map.get(claim_key)
      |> groups_with(admin_group)

    if assigned, do: "admin", else: "user"
  end

  defp groups_with(groups, admin_group) when is_list(groups) and is_binary(admin_group),
    do: admin_group in groups

  defp groups_with(_groups, _admin_group), do: false

  @doc "IdP の claims から表示名を作る。`SSO_DISPLAY_NAME_CLAIM`（既定 name）を優先する。"
  @spec resolve_display_name(map(), String.t() | nil) :: String.t()
  def resolve_display_name(claims, email) do
    claim_key = config(:display_name_claim, "name")

    from_claim = claims[claim_key] || claims["name"]
    from_email = email && email |> String.split("@") |> List.first()

    if(from_claim in [nil, ""], do: nil, else: from_claim) ||
      if(from_email in [nil, ""], do: nil, else: from_email) ||
      "SSO ユーザー"
  end

  @doc "IdP の claims からメールを取り出す。なければ nil を返す。"
  @spec resolve_email(map()) :: String.t() | nil
  def resolve_email(claims) when is_map(claims) do
    case claims["email"] do
      email when is_binary(email) and email != "" ->
        email |> String.trim() |> String.downcase()

      _other ->
        nil
    end
  end

  @doc "claims から表示名・ロール・ステータスを組み立てる。未登録ユーザーの自動作成に使う。"
  @spec build_user_params(map(), String.t()) ::
          {:ok, %{role: String.t(), display_name: String.t(), status: String.t()}}
          | {:error, :sso_not_allowed}
  def build_user_params(claims, email) do
    case config(:auto_provision, "pending") do
      false ->
        {:error, :sso_not_allowed}

      status when status in ["pending", "active"] ->
        {:ok,
         %{
           role: resolve_role(claims),
           display_name: resolve_display_name(claims, email),
           status: status
         }}

      _nil ->
        {:error, :sso_not_allowed}
    end
  end
end
