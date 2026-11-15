defmodule HelpdeskCommander.Helpdesk.AttachmentsReputationTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.HashRules
  alias HelpdeskCommander.Attachments.Reputation
  alias HelpdeskCommander.Attachments.Signatures
  alias HelpdeskCommander.Attachments.Storage
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment

  defmodule StubProvider do
    @behaviour HelpdeskCommander.Attachments.Reputation.Provider

    @impl true
    def name, do: "stub"

    @impl true
    def lookup(sha256, config) do
      if pid = Map.get(config, :test_pid) do
        send(pid, {:reputation_lookup, sha256})
      end

      Map.get(config, :result, {:ok, :unknown, nil})
    end
  end

  setup do
    company = create_company!()
    {:ok, company} = Reputation.set_company_enabled(company.id, true)
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    original_allow_skipped = Application.get_env(:helpdesk_commander, :attachment_scan_allow_skipped)
    Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, true)

    on_exit(fn ->
      Application.delete_env(:helpdesk_commander, :attachment_reputation)
      Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, original_allow_skipped)
    end)

    %{company: company, admin: admin, ticket: ticket}
  end

  test "quarantines attachment as infected when external reputation matches", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_reputation,
      enabled: true,
      provider: StubProvider,
      result: {:ok, :infected, "Malware.Example"},
      test_pid: self()
    )

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("payload.txt", "bad-content", "text/plain"))

    assert_receive {:reputation_lookup, _sha256}
    assert attachment.scan_status == "infected"
    assert attachment.scan_note =~ "infected by external reputation"
    assert attachment.scan_note =~ "Malware.Example"
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    refute File.exists?(Storage.path(:clean, attachment.storage_key))
  end

  test "precedence: deny rule skips external lookup and blocks", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    content = "blocked-content"
    sha256 = sha256_hex(content)
    {:ok, _rule} = HashRules.add(company.id, sha256, :deny, "known bad")

    Application.put_env(:helpdesk_commander, :attachment_reputation,
      enabled: true,
      provider: StubProvider,
      result: {:ok, :infected, "ShouldNotBeCalled"},
      test_pid: self()
    )

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("blocked.txt", content, "text/plain"))

    refute_receive {:reputation_lookup, _}
    assert attachment.scan_status == "blocked"
  end

  test "precedence: external infected overrides allow rule", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    content = "allowed-but-now-malicious"
    sha256 = sha256_hex(content)
    {:ok, _rule} = HashRules.add(company.id, sha256, :allow, "old allow")

    Application.put_env(:helpdesk_commander, :attachment_reputation,
      enabled: true,
      provider: StubProvider,
      result: {:ok, :infected, "ZeroDay.Hash"},
      test_pid: self()
    )

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("doc.txt", content, "text/plain"))

    assert attachment.scan_status == "infected"
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    refute File.exists?(Storage.path(:clean, attachment.storage_key))
  end

  test "precedence: external infected overrides local clean cache", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    content = "previously-clean-now-bad"
    sha256 = sha256_hex(content)
    now = DateTime.utc_now()

    {:ok, _sig} =
      Signatures.record(%{
        engine: "clamav",
        version: "1.4.3",
        signature_at: now,
        status: "ok"
      })

    {:ok, _prior} =
      TicketAttachment
      |> Ash.Changeset.for_create(:create, %{
        company_id: company.id,
        ticket_id: ticket.id,
        uploaded_by_id: admin.id,
        filename: "prior.txt",
        content_type: "text/plain",
        byte_size: byte_size(content),
        sha256: sha256,
        storage_key: "prior-key-#{System.unique_integer([:positive])}",
        scan_status: "clean",
        scanned_at: now,
        scan_engine: "clamav",
        scan_version: "1.4.3",
        signature_at: now
      })
      |> Ash.create(domain: Helpdesk, tenant: company.id, actor: admin)

    Application.put_env(:helpdesk_commander, :attachment_reputation,
      enabled: true,
      provider: StubProvider,
      result: {:ok, :infected, "LateDiscovery"},
      test_pid: self()
    )

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("again.txt", content, "text/plain"))

    assert attachment.scan_status == "infected"
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
  end

  test "fail-open on API error preserves allow rule and records note", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    content = "allow-with-api-error"
    sha256 = sha256_hex(content)
    {:ok, _rule} = HashRules.add(company.id, sha256, :allow, "trusted")

    Application.put_env(:helpdesk_commander, :attachment_reputation,
      enabled: true,
      provider: StubProvider,
      result: {:error, :timeout},
      test_pid: self()
    )

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("ok.txt", content, "text/plain"))

    assert attachment.scan_status == "clean"
    assert attachment.scan_note =~ "allowed by hash rule"
    assert attachment.scan_note =~ "reputation_fail_open:"
  end

  test "company disable switch skips external lookup during ingest", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    {:ok, _updated} = Reputation.set_company_enabled(company.id, false)

    Application.put_env(:helpdesk_commander, :attachment_reputation,
      enabled: true,
      provider: StubProvider,
      result: {:ok, :infected, "ShouldNotBeCalled"},
      test_pid: self()
    )

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("safe.txt", "hello", "text/plain"))

    refute_receive {:reputation_lookup, _}
    assert attachment.scan_status in ["pending", "skipped", "clean"]
  end

  defp sha256_hex(content) do
    :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)
  end

  defp upload(filename, content, content_type) do
    dir = Path.join(System.tmp_dir!(), "hc_rep_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, filename)
    File.write!(path, content)
    on_exit(fn -> File.rm_rf(dir) end)

    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Ingest Rep Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_user!(company_id, role) do
    unique = System.unique_integer([:positive])

    User
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id,
      email: "user#{unique}@example.com",
      display_name: "Rep User #{unique}",
      role: role,
      status: "active"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_product!(company) do
    unique = System.unique_integer([:positive])

    Product
    |> Ash.Changeset.for_create(:create, %{
      company_id: company.id,
      name: "Product #{unique}"
    })
    |> Ash.create!(domain: Helpdesk, tenant: company.id, authorize?: false)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      company_id: product.company_id,
      product_id: product.id,
      requester_id: requester.id,
      subject: "Rep test ticket",
      description: "testing reputation",
      type: "question",
      impact: "minor",
      urgency: "low"
    })
    |> Ash.create!(domain: Helpdesk, tenant: product.company_id, actor: requester)
  end
end
