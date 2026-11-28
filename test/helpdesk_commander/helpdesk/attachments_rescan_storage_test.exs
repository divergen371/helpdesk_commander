defmodule HelpdeskCommander.Helpdesk.AttachmentsRescanStorageTest do
  @moduledoc """
  再スキャン（HC-22 の更新後スキャン）と実バイトの置き場所の整合を固定する。

  過去の欠陥: `scan/1` が常に `quarantine/` を開いていたため、一度 clean になった
  （= promote で clean/ へ移動済みの）添付は、掃引後の再スキャンで「実体が無い」と
  判定されて failed に落ちていた。健全だった添付が配信停止になる。
  """
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.Storage
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_command) end)

    %{ticket: ticket, admin: admin}
  end

  test "clean になった添付は、掃引後の再スキャンでも clean のまま配信できる", %{
    ticket: ticket,
    admin: admin
  } do
    clean_scanner()
    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("a.txt", "hello", "text/plain"))
    {:ok, scanned} = Attachments.scan_attachment(attachment)
    assert scanned.scan_status == "clean"
    assert Storage.resident?(scanned.storage_key, :clean)

    assert %{enqueued: 1, failed: 0} = Attachments.rescan_outdated()

    {:ok, pending} = reload(attachment)
    assert pending.scan_status == "pending"

    {:ok, rescanned} = Attachments.scan_attachment(pending)
    assert rescanned.scan_status == "clean", "再スキャンで clean が失われた: #{rescanned.scan_note}"
    assert Attachments.downloadable?(rescanned)
    assert Storage.resident?(rescanned.storage_key, :clean)
    refute Storage.resident?(rescanned.storage_key, :quarantine)
  end

  test "再スキャンで感染を検知したら実体を隔離へ戻す", %{ticket: ticket, admin: admin} do
    clean_scanner()
    content = "EICAR test payload"

    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("b.txt", content, "text/plain"))
    {:ok, scanned} = Attachments.scan_attachment(attachment)
    assert scanned.scan_status == "clean"
    assert Storage.resident?(scanned.storage_key, :clean)

    # シグネチャ更新で同じバイトが感染と判定される状況を再現する
    infected_scanner()
    assert %{enqueued: 1} = Attachments.rescan_outdated()

    {:ok, pending} = reload(attachment)
    {:ok, rescanned} = Attachments.scan_attachment(pending)

    assert rescanned.scan_status == "infected"
    refute Attachments.downloadable?(rescanned)

    refute Storage.resident?(rescanned.storage_key, :clean),
           "感染判定なのに実体が配信ディレクトリに残っている"

    assert Storage.resident?(rescanned.storage_key, :quarantine)
  end

  test "実体が無い添付は failed にして配信しない", %{ticket: ticket, admin: admin} do
    clean_scanner()
    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("c.txt", "hello", "text/plain"))
    assert attachment.scan_status == "pending"

    :ok = Storage.delete(attachment.storage_key)

    {:ok, rescanned} = Attachments.scan_attachment(attachment)
    assert rescanned.scan_status == "failed"
    assert rescanned.scan_note =~ "missing_storage"
    refute Attachments.downloadable?(rescanned)
  end

  test "掃引は実体が消失した添付を pending に戻さず failed として数える", %{
    ticket: ticket,
    admin: admin
  } do
    clean_scanner()

    for index <- 1..2 do
      {:ok, attachment} =
        Attachments.ingest(ticket, admin, upload("d#{index}.txt", "hello", "text/plain"))

      {:ok, _} = Attachments.scan_attachment(attachment)
    end

    [attachment | _] =
      TicketAttachment
      |> Ash.read!(domain: Helpdesk, tenant: ticket.company_id)
      |> Enum.sort_by(& &1.id)

    :ok = Storage.delete(attachment.storage_key)

    assert %{enqueued: 1, failed: 1} = Attachments.rescan_outdated()
    assert %{"failed" => 1, "pending" => 1} = status_counts(ticket)
  end

  defp clean_scanner do
    # 実スキャナと同じく、対象ファイルが存在しなければ失敗する
    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_command,
      {"sh", ["-c", "test -f \"$1\" || exit 2", "--"]}
    )
  end

  defp infected_scanner do
    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_command,
      {"sh", ["-c", "grep -q EICAR \"$1\" && exit 1 || exit 0", "--"]}
    )
  end

  defp reload(attachment) do
    Ash.get(TicketAttachment, attachment.id, domain: Helpdesk, tenant: attachment.company_id)
  end

  defp status_counts(ticket) do
    TicketAttachment
    |> Ash.read!(domain: Helpdesk, tenant: ticket.company_id)
    |> Enum.frequencies_by(& &1.scan_status)
  end

  defp upload(filename, content, content_type) do
    path = Path.join(System.tmp_dir!(), "rescan-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Rescan ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Rescan Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "rescan+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Rescan #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Rescan Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "R-#{String.pad_leading(suffix, 6, "0")}"
  end
end
