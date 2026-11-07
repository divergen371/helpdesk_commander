defmodule HelpdeskCommander.Attachments.SignaturesTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Attachments.Signatures
  alias HelpdeskCommander.Helpdesk

  setup do
    original = [
      Application.get_env(:helpdesk_commander, :attachment_signature_enforce),
      Application.get_env(:helpdesk_commander, :attachment_signature_max_age_hours)
    ]

    on_exit(fn ->
      [enforce, max_age] = original
      Application.put_env(:helpdesk_commander, :attachment_signature_enforce, enforce)
      Application.put_env(:helpdesk_commander, :attachment_signature_max_age_hours, max_age)
    end)

    :ok
  end

  test "records a single signature row and updates it" do
    signature_at = DateTime.add(DateTime.utc_now(), -1, :hour)

    assert {:ok, created} =
             Signatures.record(%{
               engine: "ClamAV",
               version: "1.4.1",
               signature_at: signature_at,
               status: "ok"
             })

    assert created.engine == "ClamAV"
    assert created.version == "1.4.1"

    assert {:ok, updated} =
             Signatures.record(%{version: "1.4.2", signature_at: signature_at, status: "ok"})

    assert updated.id == created.id
    assert updated.version == "1.4.2"

    assert Ash.count!(HelpdeskCommander.Helpdesk.AttachmentSignature,
             domain: Helpdesk,
             authorize?: false
           ) == 1
  end

  test "freshness is unknown without a record" do
    assert {:ok, :unknown} = Signatures.freshness()
  end

  test "freshness is fresh within the threshold and stale beyond it" do
    Application.put_env(:helpdesk_commander, :attachment_signature_max_age_hours, 24)

    {:ok, _} =
      Signatures.record(%{signature_at: DateTime.add(DateTime.utc_now(), -2, :hour), status: "ok"})

    assert {:ok, :fresh} = Signatures.freshness()

    {:ok, _} =
      Signatures.record(%{signature_at: DateTime.add(DateTime.utc_now(), -48, :hour), status: "ok"})

    assert {:ok, :stale} = Signatures.freshness()
  end

  test "ensure_fresh warns but allows by default" do
    Application.put_env(:helpdesk_commander, :attachment_signature_enforce, false)
    {:ok, _} = Signatures.record(%{signature_at: DateTime.add(DateTime.utc_now(), -72, :hour)})

    assert :ok = Signatures.ensure_fresh()

    Application.delete_env(:helpdesk_commander, :attachment_signature_enforce)
    assert :ok = Signatures.ensure_fresh()
  end

  test "ensure_fresh rejects stale and unknown signatures when enforced" do
    Application.put_env(:helpdesk_commander, :attachment_signature_enforce, true)

    assert {:error, :signature_stale} = Signatures.ensure_fresh()

    {:ok, _} =
      Signatures.record(%{signature_at: DateTime.add(DateTime.utc_now(), -72, :hour), status: "ok"})

    assert {:error, :signature_stale} = Signatures.ensure_fresh()

    {:ok, _} =
      Signatures.record(%{signature_at: DateTime.add(DateTime.utc_now(), -1, :hour), status: "ok"})

    assert :ok = Signatures.ensure_fresh()
  end
end
