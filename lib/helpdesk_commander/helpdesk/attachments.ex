# 添付まわりはスキャナ・保存・ルールを 1 モジュールで束ねるため依存数が多い。
# credo:disable-for-next-line Credo.Check.Refactor.ModuleDependencies
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
  alias HelpdeskCommander.Attachments.HashRules
  alias HelpdeskCommander.Attachments.ScanMetadata
  alias HelpdeskCommander.Attachments.Scanner
  alias HelpdeskCommander.Attachments.Signatures
  alias HelpdeskCommander.Attachments.Storage
  alias HelpdeskCommander.Attachments.Yara
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Workers.ScanAttachmentWorker

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
    with :ok <- Signatures.ensure_fresh(),
         :ok <- FilePolicy.validate(upload),
         {:ok, stored} <- Storage.store(upload, ticket.company_id, ticket.id) do
      case HashRules.decision(ticket.company_id, stored.sha256) do
        :deny ->
          HashRules.audit_decision(:deny, ticket.company_id, stored.sha256)
          create_with_status(ticket, user, upload, stored, "blocked", "denied by hash rule")

        :allow ->
          HashRules.audit_decision(:allow, ticket.company_id, stored.sha256)
          create_with_status(ticket, user, upload, stored, "clean", "allowed by hash rule")

        nil ->
          if cache_hit?(stored.sha256) do
            HashRules.audit_decision(:cache_hit, ticket.company_id, stored.sha256)
            create_with_status(ticket, user, upload, stored, "clean", "cache hit")
          else
            with {:ok, attachment} <- create_attachment(ticket, user, upload, stored) do
              enqueue_scan(attachment)
            end
          end
      end
    end
  end

  @doc """
  スキャンを同期的に実行して結果を保存する。`ScanAttachmentWorker` から呼ばれるほか、
  テストや手動運用でも使う。既に clean / infected の添付は再検査しない。
  """
  @spec scan_attachment(TicketAttachment.t()) :: {:ok, TicketAttachment.t()} | {:error, term()}
  def scan_attachment(%TicketAttachment{scan_status: status} = attachment)
      when status in ["clean", "infected"] do
    {:ok, attachment}
  end

  def scan_attachment(%TicketAttachment{} = attachment), do: scan(attachment)

  @doc """
  失敗した添付を再スキャンする。管理者・リーダーまたはアップロード者だけが実行できる。
  ステータスを pending に戻してから非同期ジョブを積む。
  """
  @spec rescan(TicketAttachment.t(), User.t()) ::
          {:ok, TicketAttachment.t()} | {:error, :forbidden | :not_rescannable | term()}
  def rescan(%TicketAttachment{scan_status: "failed"} = attachment, %User{} = user) do
    if can_rescan?(attachment, user) do
      with {:ok, attachment} <- mark_pending(attachment) do
        enqueue_scan(attachment)
      end
    else
      {:error, :forbidden}
    end
  end

  def rescan(%TicketAttachment{}, %User{}), do: {:error, :not_rescannable}

  @doc "再スキャン可能か（failed かつ管理者・リーダーまたはアップロード者）。"
  @spec can_rescan?(TicketAttachment.t(), User.t()) :: boolean()
  def can_rescan?(%TicketAttachment{scan_status: "failed"} = attachment, %User{} = user) do
    attachment.uploaded_by_id == user.id or user.role in ["admin", "leader"]
  end

  def can_rescan?(_attachment, _user), do: false

  @doc "感染判定を誤検知として解除できるか（infected かつ同一会社の管理者・リーダー）。"
  @spec can_override_infected?(TicketAttachment.t(), User.t() | nil) :: boolean()
  def can_override_infected?(%TicketAttachment{scan_status: "infected"} = attachment, %User{} = user) do
    Authorization.same_company?(user, attachment.company_id) and user.role in ["admin", "leader"]
  end

  def can_override_infected?(_attachment, _user), do: false

  @doc """
  感染判定された添付を、管理者・リーダーが理由付きで誤検知として解除する（HC-20）。

  - 同一会社の `admin` / `leader` だけが実行できる
  - 理由は必須（空白のみは `:reason_required`）
  - 隔離ファイルを `clean/` へ移動し、状態を `clean` に更新する
  - 実行者・理由・変更前後の状態を `TicketEvent`（`attachment_quarantine_overridden`）に記録する
  """
  @spec override_infected(TicketAttachment.t(), User.t(), String.t() | nil) ::
          {:ok, TicketAttachment.t()}
          | {:error, :forbidden | :not_infected | :reason_required | term()}
  def override_infected(%TicketAttachment{scan_status: "infected"} = attachment, %User{} = user, reason) do
    with :ok <- authorize_override(attachment, user),
         {:ok, normalized_reason} <- normalize_override_reason(reason),
         :ok <- Storage.promote(attachment.storage_key),
         {:ok, updated} <- mark_overridden_clean(attachment, normalized_reason),
         :ok <- record_override_audit(attachment, updated, user, normalized_reason) do
      {:ok, updated}
    end
  end

  def override_infected(%TicketAttachment{}, %User{}, _reason), do: {:error, :not_infected}

  @doc """
  既存の clean / skipped 添付を更新後のシグネチャで再スキャンする（HC-22）。
  `:attachment_rescan_limit`（既定 500）件ずつ処理し、1 件の失敗は他へ波及させない。
  再スキャンは pending に戻すため冪等（再度呼んでも対象から外れる）。
  """
  @spec rescan_outdated(keyword()) :: %{enqueued: non_neg_integer(), failed: non_neg_integer()}
  def rescan_outdated(opts \\ []) do
    limit = Keyword.get(opts, :limit, rescan_limit())

    query =
      TicketAttachment
      |> filter(scan_status in ["clean", "skipped"])
      |> sort(inserted_at: :asc)
      |> Ash.Query.limit(limit)

    case Ash.read(query, domain: Helpdesk, authorize?: false) do
      {:ok, attachments} ->
        Enum.reduce(attachments, %{enqueued: 0, failed: 0}, fn attachment, stats ->
          case rescan_existing(attachment) do
            :ok -> %{stats | enqueued: stats.enqueued + 1}
            :error -> %{stats | failed: stats.failed + 1}
          end
        end)

      {:error, error} ->
        ErrorLog.log_error("attachments.rescan_outdated", error)
        %{enqueued: 0, failed: 0}
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

  defp create_with_status(ticket, user, upload, stored, status, note) do
    attrs = %{
      scan_status: status,
      scan_note: note,
      scanned_at: DateTime.utc_now()
    }

    case create_attachment(ticket, user, upload, stored, attrs) do
      {:ok, attachment} ->
        _promoted = if status == "clean", do: Storage.promote(attachment.storage_key)
        {:ok, attachment}

      {:error, _error} = error ->
        error
    end
  end

  defp cache_hit?(sha256) do
    case Signatures.current() do
      {:ok, %{status: "ok", signature_at: %DateTime{} = signature_at} = signature} ->
        clean_match?(sha256, signature.engine, signature.version, signature_at) and
          not infected_exists?(sha256)

      _other ->
        false
    end
  end

  defp clean_match?(sha256, engine, version, signature_at) do
    result =
      TicketAttachment
      |> filter(
        sha256 == ^sha256 and scan_status == "clean" and signature_at == ^signature_at and
          scan_engine == ^engine and scan_version == ^version
      )
      |> Ash.read_one(domain: Helpdesk, authorize?: false)

    match?({:ok, %TicketAttachment{}}, result)
  end

  defp infected_exists?(sha256) do
    result =
      TicketAttachment
      |> filter(sha256 == ^sha256 and scan_status == "infected")
      |> Ash.read_one(domain: Helpdesk, authorize?: false)

    match?({:ok, %TicketAttachment{}}, result)
  end

  defp create_attachment(ticket, user, upload, stored, extra_attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          company_id: ticket.company_id,
          ticket_id: ticket.id,
          uploaded_by_id: user.id,
          filename: Path.basename(upload.filename),
          content_type: upload.content_type,
          byte_size: stored.byte_size,
          sha256: stored.sha256,
          storage_key: stored.key
        },
        extra_attrs
      )

    result =
      TicketAttachment
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create(domain: Helpdesk, tenant: ticket.company_id, actor: user)

    case result do
      {:ok, attachment} ->
        {:ok, attachment}

      {:error, error} ->
        Storage.delete(stored.key)
        {:error, error}
    end
  end

  defp rescan_existing(%TicketAttachment{} = attachment) do
    with {:ok, pending} <- mark_pending(attachment),
         {:ok, _job} <- ScanAttachmentWorker.enqueue(pending.id) do
      :ok
    else
      {:error, error} ->
        ErrorLog.log_error("attachments.rescan_existing", error, attachment_id: attachment.id)
        _result = mark_failed(attachment, "rescan_enqueue_failed")
        :error
    end
  end

  defp mark_failed(%TicketAttachment{} = attachment, note) do
    attachment
    |> Ash.Changeset.for_update(:mark_scan, %{
      scan_status: "failed",
      scan_note: note,
      scanned_at: DateTime.utc_now()
    })
    |> Ash.update(domain: Helpdesk, tenant: attachment.company_id, authorize?: false)
  end

  defp rescan_limit do
    case Application.get_env(:helpdesk_commander, :attachment_rescan_limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _other -> 500
    end
  end

  defp enqueue_scan(%TicketAttachment{} = attachment) do
    case ScanAttachmentWorker.enqueue(attachment.id) do
      {:ok, _job} ->
        {:ok, attachment}

      {:error, error} ->
        ErrorLog.log_error("attachments.enqueue_scan", error, attachment_id: attachment.id)
        {:error, :scan_enqueue_failed}
    end
  end

  defp mark_pending(%TicketAttachment{} = attachment) do
    attachment
    |> Ash.Changeset.for_update(:mark_scan, %{
      scan_status: "pending",
      scan_note: nil,
      scanned_at: nil
    })
    |> Ash.update(domain: Helpdesk, tenant: attachment.company_id, authorize?: false)
  end

  defp scan(%TicketAttachment{} = attachment) do
    path = Storage.path(:quarantine, attachment.storage_key)
    {status, note} = scan_result(path)
    metadata = ScanMetadata.collect()

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
      scanned_at: DateTime.utc_now(),
      scan_engine: metadata.engine,
      scan_version: metadata.version,
      signature_at: metadata.signature_at
    })
    |> Ash.update(domain: Helpdesk, tenant: attachment.company_id, authorize?: false)
  end

  defp scan_result(path) do
    case Scanner.scan(path) do
      {:ok, status, note} when status in [:clean, :skipped] ->
        if Yara.enabled?() do
          yara_result(path, status, note)
        else
          {to_string(status), note}
        end

      {:ok, status, note} ->
        {to_string(status), note}

      {:error, reason} ->
        {"failed", inspect(reason)}
    end
  end

  defp yara_result(path, clam_status, clam_note) do
    case Yara.scan(path) do
      {:ok, []} ->
        {to_string(clam_status), clam_note}

      {:ok, matches} ->
        {"infected", join_notes(["YARA: " <> Enum.join(matches, ", "), clam_note])}

      {:error, reason} ->
        {"failed", join_notes(["yara: " <> inspect(reason), clam_note])}
    end
  end

  defp join_notes(notes) do
    joined = notes |> Enum.reject(&is_nil/1) |> Enum.join(" / ")
    if joined == "", do: nil, else: joined
  end

  defp authorize_override(attachment, user) do
    if can_override_infected?(attachment, user), do: :ok, else: {:error, :forbidden}
  end

  defp normalize_override_reason(reason) when is_binary(reason) do
    trimmed = String.trim(reason)
    if trimmed == "", do: {:error, :reason_required}, else: {:ok, trimmed}
  end

  defp normalize_override_reason(_reason), do: {:error, :reason_required}

  defp mark_overridden_clean(attachment, reason) do
    note =
      join_notes([
        "false_positive_override: #{reason}",
        attachment.scan_note && "previous: #{attachment.scan_note}"
      ])

    attachment
    |> Ash.Changeset.for_update(:mark_scan, %{
      scan_status: "clean",
      scan_note: note,
      scanned_at: attachment.scanned_at || DateTime.utc_now()
    })
    |> Ash.update(domain: Helpdesk, tenant: attachment.company_id, authorize?: false)
  end

  defp record_override_audit(before_attachment, after_attachment, user, reason) do
    data = %{
      attachment_id: before_attachment.id,
      filename: before_attachment.filename,
      sha256: before_attachment.sha256,
      reason: reason,
      from_status: before_attachment.scan_status,
      to_status: after_attachment.scan_status,
      previous_scan_note: before_attachment.scan_note,
      scan_engine: before_attachment.scan_engine,
      scan_version: before_attachment.scan_version
    }

    case TicketEvent
         |> Ash.Changeset.for_create(:create, %{
           event_type: "attachment_quarantine_overridden",
           data: data,
           ticket_id: before_attachment.ticket_id,
           actor_id: user.id,
           company_id: before_attachment.company_id
         })
         |> Ash.create(domain: Helpdesk, actor: user, tenant: before_attachment.company_id) do
      {:ok, _event} -> :ok
      {:error, error} -> {:error, error}
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
