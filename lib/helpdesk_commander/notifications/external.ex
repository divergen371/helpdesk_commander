defmodule HelpdeskCommander.Notifications.External do
  @moduledoc """
  Settings for external notification channels (email and chat webhook).
  """

  @config_key :helpdesk_commander
  @key __MODULE__

  @spec email_enabled?() :: boolean()
  def email_enabled?, do: Keyword.get(config(), :email_enabled, false) == true

  @spec chat_enabled?() :: boolean()
  def chat_enabled? do
    Keyword.get(config(), :chat_enabled, false) == true and is_binary(chat_webhook_url())
  end

  @spec any_enabled?() :: boolean()
  def any_enabled?, do: email_enabled?() or chat_enabled?()

  @spec chat_webhook_url() :: String.t() | nil
  def chat_webhook_url, do: Keyword.get(config(), :chat_webhook_url)

  @spec from_email() :: String.t()
  def from_email, do: Keyword.get(config(), :from_email, "noreply@helpdesk.local")

  @spec chat_req_options() :: keyword()
  def chat_req_options, do: Keyword.get(config(), :chat_req_options, [])

  defp config do
    Application.get_env(@config_key, @key, [])
  end
end
