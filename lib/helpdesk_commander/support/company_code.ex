defmodule HelpdeskCommander.Support.CompanyCode do
  @moduledoc """
  Normalizes and hashes company codes.
  """

  @format ~r/^[A-Z]-\d{6}$/

  @spec normalize(String.t()) :: {:ok, String.t()} | {:error, :invalid_format}
  # mutare:ignore[guard_drop] 非バイナリは String.trim で例外になり、挙動が同じ
  def normalize(code) when is_binary(code) do
    normalized =
      code
      |> String.trim()
      |> String.upcase()

    if Regex.match?(@format, normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_format}
    end
  end

  @spec hash(String.t()) :: {:ok, binary()} | {:error, :invalid_format}
  # mutare:ignore[guard_drop] hash/1 は :crypto.mac が非バイナリを拒否するため等価
  def hash(code) when is_binary(code) do
    with {:ok, normalized} <- normalize(code) do
      {:ok, :crypto.mac(:hmac, :sha256, hmac_secret(), normalized)}
    end
  end

  @spec hash!(String.t()) :: binary()
  # mutare:ignore[guard_drop] hash/1 は :crypto.mac が非バイナリを拒否するため等価
  def hash!(code) when is_binary(code) do
    case hash(code) do
      {:ok, hashed} -> hashed
      {:error, :invalid_format} -> raise ArgumentError, "company_code must be like A-123456"
    end
  end

  defp hmac_secret do
    Application.fetch_env!(:helpdesk_commander, :company_code_hmac_secret)
  end
end
