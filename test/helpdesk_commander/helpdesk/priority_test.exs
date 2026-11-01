defmodule HelpdeskCommander.Helpdesk.PriorityTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Priority
  alias HelpdeskCommander.Helpdesk.Product

  describe "compute/2" do
    test "returns the expected priority for every impact and urgency pair" do
      expected = %{
        "widespread" => %{"critical" => "p1", "high" => "p1", "medium" => "p2", "low" => "p3"},
        "significant" => %{"critical" => "p1", "high" => "p2", "medium" => "p2", "low" => "p3"},
        "moderate" => %{"critical" => "p2", "high" => "p3", "medium" => "p3", "low" => "p4"},
        "minor" => %{"critical" => "p3", "high" => "p3", "medium" => "p4", "low" => "p4"}
      }

      for {impact, urgencies} <- expected, {urgency, priority} <- urgencies do
        assert Priority.compute(impact, urgency) == priority
      end
    end

    test "returns nil when a dimension is missing or unknown" do
      assert Priority.compute(nil, "critical") == nil
      assert Priority.compute("widespread", nil) == nil
      assert Priority.compute("unknown", "critical") == nil
      assert Priority.compute("widespread", "unknown") == nil
    end
  end

  describe "ticket priority" do
    test "computes priority on create when impact and urgency are given" do
      {product, requester, _admin} = create_context!()

      assert {:ok, ticket} =
               Helpdesk.create_ticket(%{
                 subject: "Priority create",
                 impact: "widespread",
                 urgency: "critical",
                 product_id: product.id,
                 requester_id: requester.id
               })

      assert ticket.priority == "p1"
      assert ticket.priority_source == "auto"
    end

    test "keeps the default priority when dimensions are missing" do
      {product, requester, _admin} = create_context!()

      assert {:ok, ticket} =
               Helpdesk.create_ticket(%{
                 subject: "Priority default",
                 product_id: product.id,
                 requester_id: requester.id
               })

      assert ticket.priority == "p3"
      assert ticket.priority_source == "auto"
    end

    test "respects an explicit priority on create" do
      {product, requester, _admin} = create_context!()

      assert {:ok, ticket} =
               Helpdesk.create_ticket(%{
                 subject: "Priority manual create",
                 impact: "minor",
                 urgency: "low",
                 priority: "p2",
                 product_id: product.id,
                 requester_id: requester.id
               })

      assert ticket.priority == "p2"
      assert ticket.priority_source == "manual"
    end

    test "recomputes priority when impact or urgency changes" do
      {product, requester, admin} = create_context!()
      {:ok, ticket} = create_ticket!(product, requester, %{impact: "minor", urgency: "low"})

      assert ticket.priority == "p4"

      assert {:ok, updated} =
               Helpdesk.update_ticket(ticket, %{urgency: "critical"}, actor: admin)

      assert updated.priority == "p3"
      assert updated.priority_source == "auto"
    end

    test "an explicit priority in the same update wins over the matrix" do
      {product, requester, admin} = create_context!()
      {:ok, ticket} = create_ticket!(product, requester, %{impact: "minor", urgency: "low"})

      assert {:ok, updated} =
               Helpdesk.update_ticket(
                 ticket,
                 %{impact: "widespread", urgency: "critical", priority: "p2"},
                 actor: admin
               )

      assert updated.priority == "p2"
      assert updated.priority_source == "manual"
    end

    test "a later dimension change recalculates a manual priority" do
      {product, requester, admin} = create_context!()
      {:ok, ticket} = create_ticket!(product, requester, %{impact: "minor", urgency: "low"})
      {:ok, manual} = Helpdesk.update_ticket(ticket, %{priority: "p1"}, actor: admin)
      assert manual.priority_source == "manual"

      assert {:ok, updated} =
               Helpdesk.update_ticket(manual, %{impact: "widespread"}, actor: admin)

      assert updated.priority == "p3"
      assert updated.priority_source == "auto"
    end

    test "rejects unknown dimension values" do
      {product, requester, _admin} = create_context!()

      assert {:error, %Ash.Error.Invalid{}} =
               Helpdesk.create_ticket(%{
                 subject: "Invalid impact",
                 impact: "huge",
                 product_id: product.id,
                 requester_id: requester.id
               })
    end
  end

  defp create_ticket!(product, requester, attrs) do
    Helpdesk.create_ticket(
      Map.merge(
        %{subject: "Priority ticket", product_id: product.id, requester_id: requester.id},
        attrs
      )
    )
  end

  defp create_context! do
    company = create_company!()
    requester = create_user!(company.id)
    product = create_product!(company)
    admin = create_user!(company.id, "admin")

    {product, requester, admin}
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Priority Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role \\ "user") do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "priority+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Priority #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Priority Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
