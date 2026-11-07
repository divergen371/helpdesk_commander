defmodule HelpdeskCommander.Support.PiiHash do
  @moduledoc """
  Normalizes and hashes PII values used for lookups and unique constraints.

  Encrypted attributes cannot be compared in SQL, so `users.email` and
  `companies.name` keep a HMAC-SHA256 digest next to the ciphertext.
  """

  @spec email(String.t()) :: binary()
  # mutare:ignore[guard_drop] 非バイナリは String.trim で例外になり、挙動が同じ
  def email(value) when is_binary(value) do
    value
    |> normalize()
    |> hash()
  end

  @spec company_name(String.t()) :: binary()
  # mutare:ignore[guard_drop] 非バイナリは String.trim で例外になり、挙動が同じ
  def company_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> hash()
  end

  @spec normalize(String.t()) :: String.t()
  # mutare:ignore[guard_drop] 非バイナリは String.trim で例外になり、挙動が同じ
  def normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp hash(value) do
    :crypto.mac(:hmac, :sha256, hmac_secret(), value)
  end

  defp hmac_secret do
    Application.fetch_env!(:helpdesk_commander, :pii_hmac_secret)
  end
end
