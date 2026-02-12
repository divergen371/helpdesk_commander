defmodule HelpdeskCommander.Accounts.UserDeletionTest do
  use HelpdeskCommander.DataCase, async: true
  use Oban.Testing, repo: HelpdeskCommander.Repo

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Workers.AnonymizeExpiredUsersWorker
  alias HelpdeskCommanderWeb.CurrentUser

  describe "suspend action" do
    test "sets status to suspended and clears password" do
      user = create_active_user!()
      assert user.status == "active"

      suspended =
        user
        |> Ash.Changeset.for_update(:suspend, %{})
        |> Ash.update!(domain: Accounts)

      assert suspended.status == "suspended"
      assert suspended.password_hash == nil
      assert suspended.suspended_at != nil
      # display_name and email are preserved
      assert suspended.display_name == user.display_name
      assert suspended.email == user.email
    end
  end

  describe "anonymize action" do
    test "replaces PII and sets status to anonymized" do
      user = create_active_user!()

      suspended =
        user
        |> Ash.Changeset.for_update(:suspend, %{})
        |> Ash.update!(domain: Accounts)

      anonymized =
        suspended
        |> Ash.Changeset.for_update(:anonymize, %{})
        |> Ash.update!(domain: Accounts)

      assert anonymized.status == "anonymized"
      assert anonymized.email == "deleted-#{user.id}@anonymized.local"
      assert anonymized.display_name == "削除済みユーザー"
      assert anonymized.login_id == nil
      assert anonymized.password_hash == nil
      assert anonymized.anonymized_at != nil
    end

    test "allows re-registration with same email after anonymization" do
      user = create_active_user!()
      original_email = user.email
      company_id = user.company_id

      user
      |> Ash.Changeset.for_update(:suspend, %{})
      |> Ash.update!(domain: Accounts)
      |> Ash.Changeset.for_update(:anonymize, %{})
      |> Ash.update!(domain: Accounts)

      # Same email can be used for a new user
      new_user =
        User
        |> Ash.Changeset.for_create(:create, %{
          email: original_email,
          display_name: "New User",
          company_id: company_id,
          status: "active"
        })
        |> Ash.create!(domain: Accounts)

      assert new_user.email == original_email
    end
  end

  describe "display_label/1" do
    test "shows anonymized label for anonymized user" do
      assert CurrentUser.display_label(%User{status: "anonymized"} |> set_fields()) ==
               "削除済みユーザー"
    end

    test "shows suspended label with name" do
      user = %User{status: "suspended", display_name: "山田太郎"} |> set_fields()
      assert CurrentUser.display_label(user) == "山田太郎（無効）"
    end

    test "shows system label for system user" do
      user = %User{role: "system", status: "active", display_name: "System", email: "sys@test.com"} |> set_fields()
      assert CurrentUser.display_label(user) == "System"
    end

    test "shows name and email for active user" do
      user = %User{status: "active", display_name: "田中花子", email: "hanako@test.com", role: "user"} |> set_fields()
      assert CurrentUser.display_label(user) == "田中花子 <hanako@test.com>"
    end
  end

  describe "AnonymizeExpiredUsersWorker" do
    test "anonymizes users suspended more than 30 days ago" do
      user = create_active_user!()

      suspended =
        user
        |> Ash.Changeset.for_update(:suspend, %{})
        |> Ash.update!(domain: Accounts)

      # Manually backdate suspended_at to 31 days ago
      past = DateTime.add(DateTime.utc_now(), -31, :day)

      HelpdeskCommander.Repo.query!(
        "UPDATE users SET suspended_at = $1 WHERE id = $2",
        [past, suspended.id]
      )

      assert :ok = perform_job(AnonymizeExpiredUsersWorker, %{})

      reloaded = Ash.get!(User, %{id: user.id}, domain: Accounts)
      assert reloaded.status == "anonymized"
      assert reloaded.display_name == "削除済みユーザー"
    end

    test "does not anonymize recently suspended users" do
      user = create_active_user!()

      user
      |> Ash.Changeset.for_update(:suspend, %{})
      |> Ash.update!(domain: Accounts)

      assert :ok = perform_job(AnonymizeExpiredUsersWorker, %{})

      reloaded = Ash.get!(User, %{id: user.id}, domain: Accounts)
      assert reloaded.status == "suspended"
      assert reloaded.display_name == user.display_name
    end

    test "returns ok when no expired users exist" do
      assert :ok = perform_job(AnonymizeExpiredUsersWorker, %{})
    end
  end

  defp create_active_user! do
    email = "test+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
      company_id: company.id,
      status: "active"
    })
    |> Ash.create!(domain: Accounts)
  end

  # Helper to set required struct fields for pattern matching
  defp set_fields(%User{} = user) do
    defaults = %{
      id: 1,
      email: "test@test.com",
      display_name: "Test",
      role: "user",
      status: "active"
    }

    Map.merge(user, defaults, fn _k, v1, v2 ->
      if is_nil(v1), do: v2, else: v1
    end)
  end
end
