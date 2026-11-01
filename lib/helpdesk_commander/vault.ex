defmodule HelpdeskCommander.Vault do
  @moduledoc """
  Cloak vault used by AshCloak to encrypt PII attributes.

  Ciphers are configured per environment. Production requires
  `CLOAK_KEY` (Base64 encoded 32 byte key); development and test derive a
  local-only key so the vault works without extra setup.
  """

  use Cloak.Vault, otp_app: :helpdesk_commander
end
