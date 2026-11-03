defmodule HelpdeskCommander.Helpdesk.AnalyticsTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Analytics
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)

    now = DateTime.new!(Date.utc_today(), ~T[12:00:00], "Etc/UTC")

    %{company: company, admin: admin, product: product, now: now}
  end

  test "summarizes open, untouched, stalled, and per-assignee load", %{
    company: company,
    admin: admin,
    product: product,
    now: now
  } do
    _stalled =
      create_ticket!(product, admin, %{
        subject: "Stalled",
        status: "new",
        assignee_id: nil,
        inserted_at: DateTime.add(now, -30 * 60 * 60, :second)
      })

    _working =
      create_ticket!(product, admin, %{
        subject: "Working",
        status: "in_progress",
        assignee_id: admin.id,
        inserted_at: DateTime.add(now, -2 * 60 * 60, :second)
      })

    _resolved =
      create_ticket!(product, admin, %{
        subject: "Resolved",
        status: "resolved",
        assignee_id: admin.id,
        inserted_at: DateTime.add(now, -60 * 60, :second)
      })

    from = Date.add(Date.utc_today(), -1)
    to = Date.utc_today()

    assert {:ok, summary} =
             Analytics.summarize(company.id, from: from, to: to, now: now)

    assert summary.total_count == 3
    assert summary.open_count == 2
    assert summary.untouched_count == 1
    assert summary.stalled_count == 1
    assert summary.average_open_age_hours == 16.0

    assert summary.by_status |> Enum.map(&{&1.key, &1.count}) |> Enum.sort() == [
             {"in_progress", 1},
             {"new", 1},
             {"resolved", 1}
           ]

    by_assignee = Map.new(summary.by_assignee, &{&1.key, &1})
    assert by_assignee["未割り当て"].count == 1
    assert by_assignee[admin.display_name].count == 1
  end

  test "filters by created date", %{
    company: company,
    admin: admin,
    product: product,
    now: now
  } do
    _yesterday =
      create_ticket!(product, admin, %{
        subject: "Yesterday",
        inserted_at: DateTime.add(now, -30 * 60 * 60, :second)
      })

    _today =
      create_ticket!(product, admin, %{
        subject: "Today",
        inserted_at: DateTime.add(now, -2 * 60 * 60, :second)
      })

    assert {:ok, summary} =
             Analytics.summarize(company.id,
               from: Date.utc_today(),
               to: Date.utc_today(),
               now: now
             )

    assert summary.total_count == 1
    assert summary.open_count == 1
  end

  test "returns an empty summary when nothing matches", %{company: company} do
    assert {:ok, summary} =
             Analytics.summarize(company.id,
               from: Date.add(Date.utc_today(), -10),
               to: Date.add(Date.utc_today(), -5)
             )

    assert summary.total_count == 0
    assert summary.open_count == 0
    assert summary.average_open_age_hours == 0.0
    assert summary.by_assignee == []
  end

  test "renders the summary as CSV", %{company: company, admin: admin, product: product, now: now} do
    _ticket =
      create_ticket!(product, admin, %{
        subject: "CSV",
        status: "new",
        inserted_at: DateTime.add(now, -30 * 60 * 60, :second)
      })

    {:ok, summary} =
      Analytics.summarize(company.id,
        from: Date.add(Date.utc_today(), -1),
        to: Date.utc_today(),
        now: now
      )

    csv = Analytics.to_csv(summary)

    assert String.starts_with?(csv, "\"section\",\"key\",\"count\",\"average_age_hours\"\n")
    assert csv =~ "\"summary\",\"open_count\",1,"
    assert csv =~ "\"summary\",\"stalled_count\",1,"
    assert csv =~ "\"assignee\","
  end

  defp create_ticket!(product, requester, attrs) do
    inserted_at = Map.get(attrs, :inserted_at)
    status = Map.get(attrs, :status, "new")
    assignee_id = Map.get(attrs, :assignee_id)

    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        subject: Map.get(attrs, :subject, "Analytics ticket"),
        product_id: product.id,
        requester_id: requester.id
      })
      |> Ash.create!(domain: Helpdesk)

    ticket
    |> Ash.Changeset.for_update(:update, %{assignee_id: assignee_id})
    |> Ash.Changeset.force_change_attribute(:status, status)
    |> Ash.Changeset.force_change_attribute(:inserted_at, inserted_at)
    |> Ash.update!(domain: Helpdesk, actor: requester)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Analytics Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "analytics+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Analytics #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Analytics Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
