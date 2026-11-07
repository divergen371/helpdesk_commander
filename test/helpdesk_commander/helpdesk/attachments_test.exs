defmodule HelpdeskCommander.Helpdesk.AttachmentsTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.HashRules
  alias HelpdeskCommander.Attachments.Signatures
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
    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_timeout_ms) end)
    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_yara_command) end)

    %{company: company, admin: admin, product: product, ticket: ticket}
  end

  defp allow_skipped(value) do
    original = Application.get_env(:helpdesk_commander, :attachment_scan_allow_skipped)
    Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, value)
    on_exit(fn -> Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, original) end)
  end

  test "stores a clean file and moves it to the clean directory", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("report.txt", "hello", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "clean"
    assert attachment.filename == "report.txt"
    assert attachment.byte_size == 5
    assert attachment.sha256 == sha256("hello")

    assert File.exists?(Storage.path(:clean, attachment.storage_key))
    refute File.exists?(Storage.path(:quarantine, attachment.storage_key))
    assert {:ok, path} = Attachments.download_path(attachment)
    assert File.read!(path) == "hello"
  end

  test "keeps an infected file in quarantine and blocks download", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("bad.txt", "virus", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "infected"
    refute File.exists?(Storage.path(:clean, attachment.storage_key))
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    assert {:error, :not_ready} = Attachments.download_path(attachment)
  end

  test "marks files as skipped when no scanner is configured", %{
    ticket: ticket,
    admin: admin
  } do
    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "skipped"
    assert File.exists?(Storage.path(:clean, attachment.storage_key))
    assert Attachments.downloadable?(attachment)
  end

  test "keeps files failed and quarantined when the scanner is missing and skipped is not allowed", %{
    ticket: ticket,
    admin: admin
  } do
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)
    allow_skipped(false)

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "failed"
    assert attachment.scan_note =~ "scanner_not_configured"
    refute File.exists?(Storage.path(:clean, attachment.storage_key))
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    refute Attachments.downloadable?(attachment)
  end

  test "keeps files failed and quarantined when the scan times out", %{ticket: ticket, admin: admin} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "sleep 30"]})
    allow_skipped(false)
    Application.put_env(:helpdesk_commander, :attachment_scan_timeout_ms, 50)

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("slow.txt", "hello", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "failed"
    refute File.exists?(Storage.path(:clean, attachment.storage_key))
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    assert {:error, :not_ready} = Attachments.download_path(attachment)
  end

  test "records scanner metadata (engine, version, signature date)", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_version_command,
      {"sh", ["-c", "echo 'ClamAV 1.4.1/27480/Wed Nov  5 08:12:34 2026'"]}
    )

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_version_command) end)

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("report.txt", "hello", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "clean"
    assert attachment.scan_engine == "ClamAV"
    assert attachment.scan_version == "1.4.1"
    assert DateTime.to_iso8601(DateTime.truncate(attachment.signature_at, :second)) == "2026-11-05T08:12:34Z"
  end

  # --- HC-23: ClamAV 深掘り検査設定で隔離される検査不能・検出ファイル ---

  describe "deep scan behaviour (HC-23)" do
    test "quarantines a ZIP that contains the EICAR test file", %{ticket: ticket, admin: admin} do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, eicar_stub())

      assert {:ok, attachment} =
               Attachments.ingest(ticket, admin, upload("eicar.zip", eicar_zip(), "application/zip"))

      attachment = scan!(attachment)

      assert attachment.scan_status == "infected"
      assert attachment.scan_note =~ "EICAR"
      refute File.exists?(Storage.path(:clean, attachment.storage_key))
      assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
      refute Attachments.downloadable?(attachment)
    end

    test "quarantines Office documents with macros", %{ticket: ticket, admin: admin} do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, macro_stub())

      stub_doc = "PK" <> <<0x03, 0x04>> <> "docx payload"

      assert {:ok, attachment} =
               Attachments.ingest(
                 ticket,
                 admin,
                 upload(
                   "report.docx",
                   stub_doc,
                   "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                 )
               )

      attachment = scan!(attachment)

      assert attachment.scan_status == "infected"
      assert attachment.scan_note =~ "Macro"
      assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    end

    test "quarantines encrypted ZIP files as infected", %{ticket: ticket, admin: admin} do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, encrypted_stub())

      encrypted_zip =
        case :zip.create(~c"l.zip", [{~c"secret.txt", "secret"}], [:memory, password: ~c"waza"]) do
          {:ok, {_name, data}} -> IO.iodata_to_binary(data)
          {:ok, data} -> IO.iodata_to_binary(data)
          _other -> "PK" <> <<0x03, 0x04>> <> "encrypted"
        end

      assert {:ok, attachment} =
               Attachments.ingest(ticket, admin, upload("locked.zip", encrypted_zip, "application/zip"))

      attachment = scan!(attachment)

      assert attachment.scan_status == "infected"
      assert attachment.scan_note =~ "Encrypted"
      refute File.exists?(Storage.path(:clean, attachment.storage_key))
      assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
      refute Attachments.downloadable?(attachment)
    end

    test "keeps files failed and quarantined when the scan limits are exceeded", %{
      ticket: ticket,
      admin: admin
    } do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, exceeded_stub())

      assert {:ok, attachment} =
               Attachments.ingest(ticket, admin, upload("huge.zip", eicar_zip(), "application/zip"))

      attachment = scan!(attachment)

      assert attachment.scan_status == "failed"
      assert attachment.scan_note =~ "Exceeded"
      assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
      refute Attachments.downloadable?(attachment)
    end
  end

  defp yara_marker_stub do
    {"sh",
     [
       "-c",
       "grep -aq SUSPICIOUS_TOKEN \"$0\" && { echo \"Internal_Test $0\"; exit 0; }; exit 0"
     ]}
  end

  defp eicar_stub do
    # ClamAV のアーカイブ検査を模擬: 展開した中身に EICAR があれば検出（exit 1）
    script =
      "unzip -p \"$0\" 2>/dev/null | grep -aq EICAR && { echo \"$0: EICAR-Test-Signature FOUND\"; exit 1; }; exit 0"

    {"sh", ["-c", script]}
  end

  defp macro_stub do
    {"sh", ["-c", "echo \"$0: Macro.4452 FOUND\"; exit 1"]}
  end

  defp encrypted_stub do
    {"sh", ["-c", "echo \"$0: Encrypted.ZIP FOUND\"; exit 1"]}
  end

  defp exceeded_stub do
    {"sh", ["-c", "echo \"$0: Exceeded limits\"; exit 2"]}
  end

  defp eicar_zip do
    eicar = ~S/X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*/

    {:ok, {_name, data}} = :zip.create(~c"e.zip", [{~c"eicar.txt", eicar}], [:memory])
    IO.iodata_to_binary(data)
  end

  test "keeps files failed and quarantined on an invalid scanner configuration", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {:not_a_valid_config})
    allow_skipped(false)

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

    attachment = scan!(attachment)

    assert attachment.scan_status == "failed"
    assert attachment.scan_note =~ "invalid_scanner_config"
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
  end

  describe "signature freshness and batch rescan (HC-22)" do
    test "rejects uploads when signatures are stale and enforcement is on", %{
      ticket: ticket,
      admin: admin
    } do
      original = Application.get_env(:helpdesk_commander, :attachment_signature_enforce)
      Application.put_env(:helpdesk_commander, :attachment_signature_enforce, true)
      on_exit(fn -> Application.put_env(:helpdesk_commander, :attachment_signature_enforce, original) end)

      assert {:error, :signature_stale} =
               Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

      {:ok, _signature} =
        Signatures.record(%{signature_at: DateTime.utc_now(), status: "ok"})

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
      assert {:ok, _attachment} = Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))
    end

    test "rescans clean attachments in bounded batches and is idempotent", %{
      ticket: ticket,
      admin: admin
    } do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
      original_limit = Application.get_env(:helpdesk_commander, :attachment_rescan_limit)
      Application.put_env(:helpdesk_commander, :attachment_rescan_limit, 2)
      on_exit(fn -> Application.put_env(:helpdesk_commander, :attachment_rescan_limit, original_limit) end)

      for index <- 1..3 do
        {:ok, attachment} =
          Attachments.ingest(ticket, admin, upload("note#{index}.txt", "hello", "text/plain"))

        _attachment = scan!(attachment)
      end

      assert %{enqueued: 2, failed: 0} = Attachments.rescan_outdated()
      assert status_counts(ticket) == %{"pending" => 2, "clean" => 1}

      assert %{enqueued: 1, failed: 0} = Attachments.rescan_outdated()
      assert status_counts(ticket) == %{"pending" => 3}

      assert %{enqueued: 0, failed: 0} = Attachments.rescan_outdated()
    end
  end

  describe "YARA rules (HC-25)" do
    test "keeps a clean file clean and records a rule match as infected", %{
      ticket: ticket,
      admin: admin
    } do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
      Application.put_env(:helpdesk_commander, :attachment_yara_command, yara_marker_stub())

      assert {:ok, benign} =
               Attachments.ingest(ticket, admin, upload("benign.txt", "hello", "text/plain"))

      assert scan!(benign).scan_status == "clean"

      {:ok, malware} =
        Attachments.ingest(
          ticket,
          admin,
          upload("phish.txt", "SUSPICIOUS_TOKEN in document", "text/plain")
        )

      malware = scan!(malware)
      assert malware.scan_status == "infected"
      assert malware.scan_note =~ "YARA: Internal_Test"
      refute File.exists?(Storage.path(:clean, malware.storage_key))
      assert File.exists?(Storage.path(:quarantine, malware.storage_key))
    end

    test "fails closed when YARA errors", %{ticket: ticket, admin: admin} do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

      Application.put_env(
        :helpdesk_commander,
        :attachment_yara_command,
        {"sh", ["-c", "echo 'rule error'; exit 1"]}
      )

      {:ok, attachment} =
        Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

      attachment = scan!(attachment)
      assert attachment.scan_status == "failed"
      assert attachment.scan_note =~ "yara:"
      assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    end
  end

  describe "hash rules and clean cache (HC-24)" do
    test "denies a hash and quarantines the file immediately", %{ticket: ticket, admin: admin} do
      content = "denied content"
      {:ok, _rule} = HashRules.add(ticket.company_id, sha256(content), :deny, "test deny")

      assert {:ok, attachment} =
               Attachments.ingest(ticket, admin, upload("denied.txt", content, "text/plain"))

      assert attachment.scan_status == "blocked"
      assert attachment.scan_note =~ "denied by hash rule"
      refute File.exists?(Storage.path(:clean, attachment.storage_key))
      assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
      refute Attachments.downloadable?(attachment)
    end

    test "allows a hash and skips scanning while keeping format validation", %{
      ticket: ticket,
      admin: admin
    } do
      content = "trusted content"
      {:ok, _rule} = HashRules.add(ticket.company_id, sha256(content), :allow, "test allow")
      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

      assert {:ok, attachment} =
               Attachments.ingest(ticket, admin, upload("trusted.txt", content, "text/plain"))

      assert attachment.scan_status == "clean"
      assert attachment.scan_note =~ "allowed by hash rule"
      assert File.exists?(Storage.path(:clean, attachment.storage_key))

      assert {:error, :content_type_not_allowed} =
               Attachments.ingest(ticket, admin, upload("trusted.png", content, "text/plain"))
    end

    test "reuses a clean result for the same hash and signature", %{ticket: ticket, admin: admin} do
      content = "cache me"

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

      Application.put_env(
        :helpdesk_commander,
        :attachment_scan_version_command,
        {"sh", ["-c", "echo 'ClamAV 1.4.1/27480/Wed Nov  5 08:12:34 2026'"]}
      )

      on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_version_command) end)

      {:ok, first} = Attachments.ingest(ticket, admin, upload("first.txt", content, "text/plain"))
      first = scan!(first)
      assert first.scan_status == "clean"

      {:ok, _signature} =
        Signatures.record(%{
          engine: first.scan_engine,
          version: first.scan_version,
          signature_at: first.signature_at,
          status: "ok"
        })

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

      {:ok, second} = Attachments.ingest(ticket, admin, upload("second.txt", content, "text/plain"))

      assert second.scan_status == "clean"
      assert second.scan_note == "cache hit"
      assert File.exists?(Storage.path(:clean, second.storage_key))
    end

    test "does not use the cache when the signature is unknown", %{ticket: ticket, admin: admin} do
      content = "no signature cache"

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
      {:ok, first} = Attachments.ingest(ticket, admin, upload("first.txt", content, "text/plain"))
      assert scan!(first).scan_status == "clean"

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

      {:ok, second} = Attachments.ingest(ticket, admin, upload("second.txt", content, "text/plain"))
      assert second.scan_status == "pending"
    end
  end

  describe "manual rescan (HC-18)" do
    test "returns a failed attachment to pending and enqueues a job", %{
      ticket: ticket,
      admin: admin
    } do
      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 2"]})

      {:ok, attachment} =
        Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

      attachment = scan!(attachment)
      assert attachment.scan_status == "failed"
      assert Attachments.can_rescan?(attachment, admin)

      assert {:ok, pending} = Attachments.rescan(attachment, admin)
      assert pending.scan_status == "pending"
    end

    test "allows the uploader to rescan", %{company: company, ticket: ticket} do
      requester = create_user!(company.id, "customer")

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 2"]})

      external_ticket = create_ticket!(create_product!(company), requester)

      {:ok, attachment} =
        Attachments.ingest(external_ticket, requester, upload("note.txt", "hello", "text/plain"))

      attachment = scan!(attachment)
      assert Attachments.can_rescan?(attachment, requester)
      assert {:ok, _pending} = Attachments.rescan(attachment, requester)
    end

    test "forbids unrelated users and non-failed attachments", %{company: company, ticket: ticket, admin: admin} do
      other = create_user!(company.id, "customer")

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 2"]})

      {:ok, failed} = Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))
      failed = scan!(failed)

      refute Attachments.can_rescan?(failed, other)
      assert {:error, :forbidden} = Attachments.rescan(failed, other)

      Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
      {:ok, clean} = Attachments.ingest(ticket, admin, upload("ok.txt", "hello", "text/plain"))
      clean = scan!(clean)

      assert {:error, :not_rescannable} = Attachments.rescan(clean, admin)
    end
  end

  test "rejects a file whose content does not match its extension", %{ticket: ticket, admin: admin} do
    # 実行バイナリ（MZ + NUL を含むペイロード）を .txt に偽装したケース（HC-19）
    exe = "MZ" <> <<0x90, 0x00, 0x03, 0xFF>> <> "payload"

    assert {:error, :content_magic_mismatch} =
             Attachments.ingest(ticket, admin, upload("run.txt", exe, "text/plain"))

    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  test "rejects disallowed extensions and MIME types", %{ticket: ticket, admin: admin} do
    assert {:error, :extension_not_allowed} =
             Attachments.ingest(ticket, admin, upload("script.exe", "MZ", "application/octet-stream"))

    assert {:error, :content_type_not_allowed} =
             Attachments.ingest(ticket, admin, upload("image.png", "not-an-image", "text/plain"))

    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  test "limits downloads to users who can see the ticket", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))
    attachment = scan!(attachment)

    assert {:ok, fetched} = Attachments.fetch_for_download(attachment.id, admin)
    assert fetched.id == attachment.id

    other_company_user = create_user_in_new_company!()
    assert {:error, :not_found} = Attachments.fetch_for_download(attachment.id, other_company_user)

    external_requester = create_user!(company.id, "customer")
    external_ticket = create_ticket!(create_product!(company), external_requester)

    {:ok, external_attachment} =
      Attachments.ingest(external_ticket, external_requester, upload("photo.png", png_bytes(), "image/png"))

    {_, external_attachment} = {nil, scan!(external_attachment)}

    assert {:ok, _attachment} = Attachments.fetch_for_download(external_attachment.id, external_requester)

    other_external = create_user!(company.id, "customer")
    assert {:error, :forbidden} = Attachments.fetch_for_download(external_attachment.id, other_external)
  end

  test "deletes the record and the stored file", %{ticket: ticket, admin: admin} do
    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))
    attachment = scan!(attachment)
    path = Storage.path(:clean, attachment.storage_key)

    assert :ok = Attachments.delete(attachment, admin)
    refute File.exists?(path)
    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  defp status_counts(ticket) do
    TicketAttachment
    |> Ash.read!(domain: Helpdesk, tenant: ticket.company_id)
    |> Enum.frequencies_by(& &1.scan_status)
  end

  defp scan!(attachment) do
    {:ok, scanned} = Attachments.scan_attachment(attachment)
    scanned
  end

  defp upload(filename, content, content_type) do
    path = Path.join(System.tmp_dir!(), "attachment-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  defp png_bytes do
    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, "IHDR">>
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Attachment ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_user_in_new_company! do
    company = create_company!()
    create_user!(company.id, "admin")
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "attachment+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Attachment #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
