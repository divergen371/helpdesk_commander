defmodule HelpdeskCommander.Attachments.HashRulesTest do
  use HelpdeskCommander.DataCase, async: false

  import ExUnit.CaptureLog

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Attachments.HashRules

  @sha String.duplicate("a", 64)
  @other_sha String.duplicate("b", 64)

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    company = create_company!()
    %{company: company}
  end

  test "adds, updates and removes a rule, writing audit logs" do
    log =
      capture_log(fn ->
        assert {:ok, rule} = HashRules.add(nil, @sha, :deny, "known bad")
        assert rule.action == "deny"
        assert rule.company_id == nil

        assert {:ok, updated} = HashRules.add(nil, @sha, :allow, "false positive")
        assert updated.id == rule.id
        assert updated.action == "allow"

        assert {:ok, [_rule]} = HashRules.list(12_345)
        assert :ok = HashRules.remove(updated)
        assert {:ok, []} = HashRules.list(12_345)
      end)

    assert log =~ "attachment_hash_rules created"
    assert log =~ "attachment_hash_rules updated"
    assert log =~ "attachment_hash_rules deleted"
  end

  test "deny wins over allow across global and company scopes", %{company: company} do
    assert {:ok, _} = HashRules.add(nil, @sha, :deny, "global deny")
    assert {:ok, _} = HashRules.add(company.id, @sha, :allow, "company allow")

    assert HashRules.decision(company.id, @sha) == :deny
    assert HashRules.decision(99, @sha) == :deny
    assert HashRules.decision(company.id, @other_sha) == nil
  end

  test "company rules apply to that company only", %{company: company} do
    assert {:ok, _} = HashRules.add(company.id, @sha, :allow, "trusted")

    assert HashRules.decision(company.id, @sha) == :allow
    assert HashRules.decision(99, @sha) == nil
  end

  test "rejects invalid actions and records decisions" do
    assert {:error, :invalid_action} = HashRules.add(nil, @sha, :other, nil)

    log =
      capture_log(fn ->
        assert :ok = HashRules.audit_decision(:deny, 42, @sha)
      end)

    assert log =~ "attachment_hash_rules decision"
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Hash Rule Company #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts)
  end
end
