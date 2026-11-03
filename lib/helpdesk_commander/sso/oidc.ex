defmodule HelpdeskCommander.SSO.Oidc do
  @moduledoc """
  OIDC（Authorization Code Flow）の実行部。Assent の `Assent.Strategy.OIDC` を使う。

  - `authorize_url/0`: IdP の Authorization URL と state / nonce を返す
  - `callback/2`: code と state を検証して ID Token から claims を取り出す
  """

  alias HelpdeskCommander.SSO
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec authorize_url() :: {:ok, %{url: String.t(), session_params: map()}} | {:error, atom()}
  def authorize_url do
    if SSO.enabled?() do
      nonce = nonce()
      config = Keyword.put(base_config(), :nonce, nonce)

      case Assent.Strategy.OIDC.authorize_url(config) do
        {:ok, %{url: url, session_params: session_params}} ->
          {:ok, %{url: url, session_params: Map.put(session_params, :nonce, nonce)}}

        {:error, error} ->
          handle_error("sso.authorize_url", error)
      end
    else
      {:error, :sso_disabled}
    end
  end

  @doc """
  Callback 実行。`session_params` には `authorize_url/0` が返した state / nonce を渡す。
  成功時は ID Token の claims（email / sub / groups 等）を返す。
  """
  @spec callback(map(), map()) :: {:ok, map()} | {:error, atom()}
  def callback(params, session_params) do
    if SSO.enabled?() do
      config = Keyword.put(base_config(), :session_params, Map.new(session_params))

      case Assent.Strategy.OIDC.callback(config, params) do
        {:ok, %{user: claims}} ->
          {:ok, claims}

        {:error, error} ->
          handle_error("sso.callback", error)
      end
    else
      {:error, :sso_disabled}
    end
  end

  defp base_config do
    base = [
      client_id: SSO.config(:client_id),
      client_secret: SSO.config(:client_secret),
      base_url: SSO.config(:base_url),
      redirect_uri: SSO.config(:redirect_uri) || "http://localhost:4000/auth/sso/callback",
      id_token_signed_response_alg: SSO.config(:id_token_signed_response_alg, "RS256")
    ]

    maybe_put_http_adapter(base)
  end

  defp maybe_put_http_adapter(config) do
    case SSO.config(:http_adapter) do
      nil -> config
      adapter -> Keyword.put(config, :http_adapter, adapter)
    end
  end

  defp nonce do
    case SSO.config(:fixed_nonce) do
      nil ->
        16
        |> :crypto.strong_rand_bytes()
        |> Base.encode64(padding: false)

      fixed ->
        fixed
    end
  end

  defp handle_error(stage, error) do
    ErrorLog.log_error(stage, error)
    {:error, :sso_failed}
  end
end
