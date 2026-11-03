defmodule HelpdeskCommanderWeb.Api.FallbackController do
  @moduledoc """
  API の共通エラーレスポンス。
  """

  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec call(Plug.Conn.t(), {:error, :unauthorized}) :: Plug.Conn.t()
  def call(conn, {:error, :unauthorized}) do
    respond(conn, 401, "unauthorized", "認証が必要です")
  end

  @spec call(Plug.Conn.t(), {:error, :forbidden}) :: Plug.Conn.t()
  def call(conn, {:error, :forbidden}) do
    respond(conn, 403, "forbidden", "アクセス権限がありません")
  end

  @spec call(Plug.Conn.t(), {:error, :not_found}) :: Plug.Conn.t()
  def call(conn, {:error, :not_found}) do
    respond(conn, 404, "not_found", "リソースが見つかりません")
  end

  @spec call(Plug.Conn.t(), {:error, :already_promoted}) :: Plug.Conn.t()
  def call(conn, {:error, :already_promoted}) do
    respond(conn, 422, "already_promoted", "すでに昇格済みです")
  end

  @spec call(Plug.Conn.t(), {:error, :invalid_status}) :: Plug.Conn.t()
  def call(conn, {:error, :invalid_status}) do
    respond(conn, 422, "validation_failed", "不正なステータスです")
  end

  @spec call(Plug.Conn.t(), {:error, Ash.Error.Forbidden.t()}) :: Plug.Conn.t()
  def call(conn, {:error, %Ash.Error.Forbidden{}}) do
    respond(conn, 403, "forbidden", "アクセス権限がありません")
  end

  @spec call(Plug.Conn.t(), {:error, Ash.Error.Invalid.t()}) :: Plug.Conn.t()
  def call(conn, {:error, %Ash.Error.Invalid{} = error}) do
    if stale_error?(error) do
      respond(conn, 409, "conflict", "更新競合が発生しました")
    else
      payload = %{
        error: %{
          code: "validation_failed",
          message: "入力内容を確認してください",
          fields: fields(error)
        }
      }

      conn |> put_status(422) |> json(payload)
    end
  end

  @spec call(Plug.Conn.t(), {:error, Ecto.Changeset.t()}) :: Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    fields = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    payload = %{
      error: %{code: "validation_failed", message: "入力内容を確認してください", fields: fields}
    }

    conn |> put_status(422) |> json(payload)
  end

  @spec call(Plug.Conn.t(), {:error, term()}) :: Plug.Conn.t()
  def call(conn, {:error, reason}) do
    ErrorLog.log_error("api.fallback", reason)
    respond(conn, 500, "internal_error", "予期しないエラーが発生しました")
  end

  defp respond(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end

  defp stale_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn error ->
      message = String.downcase(error_message(error))
      String.contains?(message, "lock") or String.contains?(message, "stale")
    end)
  end

  defp fields(%Ash.Error.Invalid{errors: errors}) do
    Enum.reduce(errors, %{}, fn error, acc ->
      key = field_name(error)
      current = Map.get(acc, key, [])
      Map.put(acc, key, [error_message(error) | current])
    end)
  end

  defp field_name(%{field: field}) when is_atom(field), do: Atom.to_string(field)
  defp field_name(%{field: field}) when is_binary(field), do: field
  defp field_name(_error), do: "_other"

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(error), do: Exception.message(error)
end
