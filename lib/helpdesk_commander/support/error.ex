defmodule HelpdeskCommander.Support.Error do
  @moduledoc false

  require Logger

  @spec log_error(String.t(), term(), keyword()) :: :ok
  def log_error(context, error, metadata \\ []) do
    Logger.error("[#{context}] #{format_error(error)}", metadata)
  end

  @spec log_warn(String.t(), term(), keyword()) :: :ok
  def log_warn(context, error, metadata \\ []) do
    Logger.warning("[#{context}] #{format_error(error)}", metadata)
  end

  defp format_error(%{__exception__: true} = error), do: Exception.message(error)
  defp format_error(error), do: inspect(error)
end
