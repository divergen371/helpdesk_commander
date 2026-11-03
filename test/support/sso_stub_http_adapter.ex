defmodule HelpdeskCommander.SSOStubHTTPAdapter do
  @moduledoc """
  SSO テスト用の Assent HTTP アダプタ。IdP（openid-configuration / token）を擬似する。

  - `set_user/2`（または set_user/3）で次に発行する ID Token の claims を切り替える
  - ID Token は HS256 で署名し、test config の client_secret で Assent 側が検証する
  """

  @behaviour Assent.HTTPAdapter

  @openid_configuration %{
    "issuer" => "http://idp.localhost",
    "authorization_endpoint" => "http://idp.localhost/authorize",
    "token_endpoint" => "http://idp.localhost/token",
    "userinfo_endpoint" => "http://idp.localhost/userinfo",
    "jwks_uri" => "http://idp.localhost/jwks",
    "token_endpoint_auth_methods_supported" => [
      "client_secret_basic",
      "client_secret_post"
    ]
  }

  def set_user(email, groups \\ [], name \\ "SSO Test User") do
    Process.put(:sso_stub_user, %{"email" => email, "groups" => groups, "name" => name})
  end

  @impl true
  def request(method, url, body, _headers, _opts) do
    case {method, String.contains?(url, "/.well-known/openid-configuration"), String.contains?(url, "/token")} do
      {:get, true, false} ->
        respond(200, Jason.encode!(@openid_configuration))

      {:post, _, true} ->
        respond(200, token_response())

      _other ->
        respond(404, Jason.encode!(%{"error" => "sso_stub_unmatched", "url" => url, "body" => body}))
    end
  end

  defp token_response do
    claims =
      %{
        "iss" => "http://idp.localhost",
        "sub" => "sso-sub-1",
        "aud" => "test-client-id",
        "exp" => System.system_time(:second) + 60,
        "iat" => System.system_time(:second),
        "nonce" => HelpdeskCommander.SSO.config(:fixed_nonce)
      }
      |> Map.merge(stub_user())

    {:ok, id_token} =
      Assent.Strategy.sign_jwt(
        claims,
        "HS256",
        HelpdeskCommander.SSO.config(:client_secret),
        []
      )

    Jason.encode!(%{
      "access_token" => "stub-access-token",
      "id_token" => id_token,
      "token_type" => "Bearer",
      "expires_in" => 3600
    })
  end

  defp stub_user do
    Process.get(:sso_stub_user) || %{"email" => "nobody@example.com", "groups" => []}
  end

  defp respond(status, body) do
    {:ok,
     %Assent.HTTPAdapter.HTTPResponse{
       status: status,
       headers: [{"content-type", "application/json"}],
       body: body
     }}
  end
end
