defmodule HelpdeskCommanderWeb.AuthToken do
  @moduledoc """
  API 用の Phoenix.Token。

  サインイン成功時に発行し、`Authorization: Bearer <token>` で送る。
  """

  @salt "api user token"
  @max_age 30 * 24 * 60 * 60

  @spec sign(HelpdeskCommander.Accounts.User.t()) :: String.t()
  def sign(%HelpdeskCommander.Accounts.User{} = user) do
    Phoenix.Token.sign(endpoint(), @salt, %{
      user_id: user.id,
      company_id: user.company_id,
      role: user.role
    })
  end

  @spec verify(String.t()) ::
          {:ok, %{user_id: integer(), company_id: integer(), role: String.t()}}
          | {:error, term()}
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(endpoint(), @salt, token, max_age: @max_age)
  end

  def verify(_token), do: {:error, :invalid_token}

  @spec max_age() :: 2_592_000
  def max_age, do: @max_age

  defp endpoint, do: HelpdeskCommanderWeb.Endpoint
end
