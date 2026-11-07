defmodule HelpdeskCommander.AuthorizationTest do
  use ExUnit.Case, async: true

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization

  defp user(role, company_id \\ 1), do: %User{role: role, company_id: company_id}

  test "privileged_role? accepts users and role strings" do
    assert Authorization.privileged_role?(user("admin"))
    assert Authorization.privileged_role?(user("leader"))
    refute Authorization.privileged_role?(user("user"))
    assert Authorization.privileged_role?("admin")
    refute Authorization.privileged_role?("customer")
    refute Authorization.privileged_role?(nil)
    refute Authorization.privileged_role?(:admin)
  end

  test "external? accepts users and role strings" do
    assert Authorization.external?(user("customer"))
    assert Authorization.external?(user("external"))
    refute Authorization.external?(user("admin"))
    assert Authorization.external?("customer")
    refute Authorization.external?("leader")
    refute Authorization.external?(nil)
  end

  test "internal? rejects non-binary and non-user values" do
    assert Authorization.internal?(user("admin"))
    refute Authorization.internal?(user("customer"))
    assert Authorization.internal?("leader")
    refute Authorization.internal?("customer")
    refute Authorization.internal?(nil)
    refute Authorization.internal?(:admin)
  end

  test "same_company? requires a matching company id" do
    assert Authorization.same_company?(user("admin", 7), 7)
    refute Authorization.same_company?(user("admin", 7), 8)
    refute Authorization.same_company?(user("admin", 7), nil)
    refute Authorization.same_company?(nil, 7)
  end

  test "privileged_for_company? requires both role and company" do
    assert Authorization.privileged_for_company?(user("admin", 7), 7)
    refute Authorization.privileged_for_company?(user("admin", 7), 8)
    refute Authorization.privileged_for_company?(user("user", 7), 7)
    refute Authorization.privileged_for_company?(nil, 7)
  end
end
