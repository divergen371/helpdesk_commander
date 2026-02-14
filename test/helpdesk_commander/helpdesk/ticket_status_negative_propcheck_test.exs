defmodule HelpdeskCommander.Helpdesk.TicketStatusNegativePropCheckTest do
  use HelpdeskCommander.DataCase, async: true
  use PropCheck

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  @statuses ~w(new triage in_progress waiting resolved verified closed)
  @allowed_transitions %{
    "new" => ~w(triage in_progress waiting resolved),
    "triage" => ~w(in_progress waiting resolved),
    "in_progress" => ~w(waiting resolved),
    "waiting" => ~w(in_progress resolved),
    "resolved" => ~w(in_progress waiting verified closed),
    "verified" => [],
    "closed" => []
  }
  @invalid_transition_pairs for from <- @statuses,
                                to <- @statuses,
                                from != to and to not in Map.get(@allowed_transitions, from, []),
                                do: {from, to}
  @valid_transition_pairs for from <- @statuses,
                              to <- Map.get(@allowed_transitions, from, []),
                              do: {from, to}

  property "propcheck: invalid status transitions are rejected", numtests: 20 do
    forall {from, to} <- elements(@invalid_transition_pairs) do
      {user, admin, ticket} = create_context!()
      ticket = force_status!(ticket, from, user, admin)

      assert {:error, _error} =
               ticket
               |> Ash.Changeset.for_update(:set_status, %{status: to, actor_id: admin.id})
               |> Ash.update(domain: Helpdesk)

      true
    end
  end

  defp actor_id_for_status(status, _user_id, admin_id) when status in ["verified", "closed"],
    do: admin_id

  defp actor_id_for_status(_status, user_id, _admin_id), do: user_id

  property "propcheck: valid status transitions are accepted", numtests: 20 do
    forall {from, to} <- elements(@valid_transition_pairs) do
      {user, admin, ticket} = create_context!()
      ticket = force_status!(ticket, from, user, admin)
      actor_id = actor_id_for_status(to, user.id, admin.id)

      assert {:ok, updated} =
               ticket
               |> Ash.Changeset.for_update(:set_status, %{status: to, actor_id: actor_id})
               |> Ash.update(domain: Helpdesk)

      assert updated.status == to
      true
    end
  end

  defp force_status!(%Ticket{} = ticket, "new", _user, _admin), do: ticket
  defp force_status!(%Ticket{} = ticket, "triage", user, _admin), do: set_status!(ticket, "triage", user.id)
  defp force_status!(%Ticket{} = ticket, "in_progress", user, _admin), do: set_status!(ticket, "in_progress", user.id)
  defp force_status!(%Ticket{} = ticket, "waiting", user, _admin), do: set_status!(ticket, "waiting", user.id)
  defp force_status!(%Ticket{} = ticket, "resolved", user, _admin), do: set_status!(ticket, "resolved", user.id)

  defp force_status!(%Ticket{} = ticket, "verified", user, admin) do
    ticket
    |> set_status!("resolved", user.id)
    |> set_status!("verified", admin.id)
  end

  defp force_status!(%Ticket{} = ticket, "closed", user, admin) do
    ticket
    |> set_status!("resolved", user.id)
    |> set_status!("closed", admin.id)
  end

  defp set_status!(%Ticket{} = ticket, status, actor_id) do
    ticket
    |> Ash.Changeset.for_update(:set_status, %{status: status, actor_id: actor_id})
    |> Ash.update!(domain: Helpdesk)
  end

  defp create_context! do
    company = Accounts.Auth.default_company!()
    user = create_user!(company.id, "user")
    admin = create_user!(company.id, "admin")
    ticket = create_ticket!(user)
    {user, admin, ticket}
  end

  defp create_user!(company_id, role) do
    email = "status+#{role}+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Status #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Status Test",
      description: "Status Test",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
