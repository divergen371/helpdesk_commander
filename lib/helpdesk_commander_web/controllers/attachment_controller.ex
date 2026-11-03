defmodule HelpdeskCommanderWeb.AttachmentController do
  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk.Attachments

  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"id" => id}) do
    case current_user(conn) do
      %User{} = user ->
        case Attachments.fetch_for_download(id, user) do
          {:ok, attachment} ->
            send_attachment(conn, attachment)

          {:error, :forbidden} ->
            send_resp(conn, 403, "この添付ファイルを取得する権限がありません")

          {:error, :not_ready} ->
            send_resp(conn, 403, "この添付ファイルはまだ取得できません")

          {:error, _reason} ->
            send_resp(conn, 404, "添付ファイルが見つかりません")
        end

      nil ->
        conn
        |> put_flash(:error, "ログインが必要です")
        |> redirect(to: ~p"/sign-in")
        |> halt()
    end
  end

  defp send_attachment(conn, attachment) do
    case Attachments.download_path(attachment) do
      {:ok, path} ->
        conn
        |> put_resp_content_type(attachment.content_type)
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{safe_filename(attachment.filename)}\""
        )
        |> send_file(200, path)

      {:error, _reason} ->
        send_resp(conn, 403, "この添付ファイルはまだ取得できません")
    end
  end

  defp safe_filename(filename) do
    value =
      filename
      |> to_string()
      |> Path.basename()
      |> String.replace(["\"", "\r", "\n"], "_")

    case value do
      "" -> "attachment"
      safe -> safe
    end
  end

  defp current_user(conn) do
    case get_session(conn, :user_id) do
      nil ->
        nil

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, %User{status: "active"} = user} ->
            user

          _result ->
            nil
        end
    end
  end
end
