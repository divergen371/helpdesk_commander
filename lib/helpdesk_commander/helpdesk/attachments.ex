defmodule HelpdeskCommander.Helpdesk.Attachments do
  @moduledoc """
  チケット添付ファイルの保存・スキャン・取得可否を扱う。

  アップロードは隔離ディレクトリへ保存し、スキャン結果が clean または skipped の
  ときだけ clean ディレクトリへ移してダウンロードを許可する。infected / failed は
  隔離したままにし、取得を拒否する。
  """

  import Ash.Query

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.FilePolicy
  alias HelpdeskCommander.Attachments.Scanner
  alias HelpdeskCommander.Attachments.Storage
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment

  @downloadable ~w(clean skipped)

  @spec list_for_ticket(Ticket.t(), keyword()) ::
          {:ok, [TicketAttachment.t()]} | {:error, term()}
  def list_for_ticket(%Ticket{id: ticket_id, company_id: company_id}, opts \\ []) do
    TicketAttachment
    |> filter(ticket_id == ^ticket_id)
    |> sort(inserted_at: :desc)
    |> Ash.read(domain: Helpdesk, tenant: company_id, authorize?: Keyword.get(opts, :authorize?, true))
  end

  @spec ingest(Ticket.t(), User.t(), Plug.Upload.t()) ::
          {:ok, TicketAttachment.t()} | {:error, term()}
  def ingest(%Ticket{} = ticket, %User{} = user, %Plug.Upload{} = upload) do
    with :ok <- FilePolicy.validate(upload),
         {:ok, stored} <- Storage.store(upload, ticket.company_id, ticket.id),
         {:ok, attachment} <- create_attachment(ticket, user, upload, stored) do
      scan(attachment)
    end
  end

  @spec downloadable?(TicketAttachment.t()) :: boolean()
  def downloadable?(%TicketAttachment{scan_status: status}), do: status in @downloadable

  @spec download_path(TicketAttachment.t()) :: {:ok, String.t()} | {:error, term()}
  def download_path(%TicketAttachment{scan_status: status, storage_key: key}) do
    if status in @downloadable do
      {:ok, Storage.path(:clean, key)}
    else
      {:error, :not_ready}
    end
  end

  @doc "ダウンロード対象の添付を、チケットの閲覧権限で取得する。"
  @spec fetch_for_download(term(), User.t()) ::
          {:ok, TicketAttachment.t()} | {:error, :not_found | :forbidden | :not_ready}
  def fetch_for_download(id, %User{} = user) do
    with {attachment_id, _rest} <- parse_id(id),
         {:ok, %TicketAttachment{} = attachment} <- read_attachment(attachment_id, user),
         {:ok, %Ticket{} = ticket} <- read_ticket(attachment.ticket_id, user) do
      cond do
        not can_access_ticket?(ticket, user) -> {:error, :forbidden}
        not downloadable?(attachment) -> {:error, :not_ready}
        true -> {:ok, attachment}
      end
    else
      :error -> {:error, :not_found}
      {:ok, nil} -> {:error, :not_found}
      {:error, _error} -> {:error, :not_found}
    end
  end

  @spec delete(TicketAttachment.t(), User.t()) :: :ok | {:error, term()}
  def delete(%TicketAttachment{} = attachment, %User{} = user) do
    case Ash.destroy(attachment,
           domain: Helpdesk,
           tenant: attachment.company_id,
           actor: user
         ) do
      :ok ->
        Storage.delete(attachment.storage_key)
        :ok

      {:ok, _deleted} ->
        Storage.delete(attachment.storage_key)
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  @doc "チケット閲覧権限（社内は同一会社、外部は依頼者本人）。"
  @spec can_access_ticket?(Ticket.t(), User.t()) :: boolean()
  def can_access_ticket?(%Ticket{} = ticket, %User{} = user) do
    cond do
      ticket.visibility_scope == "global" -> true
      not Authorization.same_company?(user, ticket.company_id) -> false
      Authorization.external?(user) -> ticket.requester_id == user.id
      true -> true
    end
  end

  defp read_attachment(id, user) do
    TicketAttachment
    |> filter(id == ^id)
    |> Ash.read_one(domain: Helpdesk, tenant: user.company_id)
  end

  defp read_ticket(id, user) do
    Ticket
    |> filter(id == ^id)
    |> Ash.read_one(domain: Helpdesk, tenant: user.company_id)
  end

  defp create_attachment(ticket, user, upload, stored) do
    result =
      TicketAttachment
      |> Ash.Changeset.for_create(:create, %{
        company_id: ticket.company_id,
        ticket_id: ticket.id,
        uploaded_by_id: user.id,
        filename: Path.basename(upload.filename),
        content_type: upload.content_type,
        byte_size: stored.byte_size,
        sha256: stored.sha256,
        storage_key: stored.key
      })
      |> Ash.create(domain: Helpdesk, tenant: ticket.company_id, actor: user)

    case result do
      {:ok, attachment} ->
        {:ok, attachment}

      {:error, error} ->
        Storage.delete(stored.key)
        {:error, error}
    end
  end

  defp scan(%TicketAttachment{} = attachment) do
    path = Storage.path(:quarantine, attachment.storage_key)
    {status, note} = scan_result(path)

    _promoted =
      if status in @downloadable do
        Storage.promote(attachment.storage_key)
      else
        :ok
      end

    attachment
    |> Ash.Changeset.for_update(:mark_scan, %{
      scan_status: status,
      scan_note: note,
      scanned_at: DateTime.utc_now()
    })
    |> Ash.update(domain: Helpdesk, tenant: attachment.company_id, authorize?: false)
  end

  defp scan_result(path) do
    case Scanner.scan(path) do
      {:ok, status, note} -> {to_string(status), note}
      {:error, reason} -> {"failed", inspect(reason)}
    end
  end

  defp parse_id(id) when is_integer(id), do: {id, ""}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, rest} -> {value, rest}
      :error -> :error
    end
  end

  defp parse_id(_id), do: :error
end
