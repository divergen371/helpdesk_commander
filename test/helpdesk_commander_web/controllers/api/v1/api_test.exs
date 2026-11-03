defmodule HelpdeskCommanderWeb.Api.V1Test do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  @password "api-password-123"

  describe "POST /api/v1/sign-in" do
    test "returns a bearer token for valid credentials", %{conn: conn} do
      company_code = unique_company_code()
      company = create_company!(company_code)
      user = create_user!(company.id, "admin", @password)

      conn = sign_in(conn, company_code, user.email, @password)

      assert %{"token" => token, "user" => %{"role" => "admin"}} = json_response(conn, 200)
      assert is_binary(token) and token != ""
    end

    test "rejects invalid credentials", %{conn: conn} do
      company_code = unique_company_code()
      company = create_company!(company_code)
      user = create_user!(company.id, "admin", @password)

      conn =
        post(conn, "/api/v1/sign-in", %{
          company_code: company_code,
          login: user.email,
          password: "wrong"
        })

      assert json_response(conn, 401)["error"]["code"] == "invalid_credentials"
    end
  end

  describe "authenticated tickets" do
    setup %{conn: conn} do
      company_code = unique_company_code()
      company = create_company!(company_code)
      admin = create_user!(company.id, "admin", @password)
      product = create_product!(company)
      conn = log_in_with_token(conn, company_code, admin)
      {:ok, conn: conn, company: company, admin: admin, product: product, company_code: company_code}
    end

    test "creates and lists tickets", %{conn: conn, product: product} do
      conn =
        post(conn, "/api/v1/tickets", %{
          ticket: %{
            subject: "API ticket",
            description: "from API",
            type: "question",
            product_id: product.id,
            impact: "widespread",
            urgency: "critical"
          }
        })

      body = json_response(conn, 201)
      ticket = body["ticket"]
      assert ticket["subject"] == "API ticket"
      assert ticket["priority"] == "p1"
      assert ticket["priority_source"] == "auto"
      assert ticket["status"] == "new"

      conn = get(recycle(conn), "/api/v1/tickets")
      body = json_response(conn, 200)
      assert body["meta"]["total_count"] >= 1
      assert Enum.any?(body["tickets"], &(&1["public_id"] == ticket["public_id"]))

      conn = get(recycle(conn), "/api/v1/tickets?q=API")
      assert json_response(conn, 200)["meta"]["total_count"] >= 1
    end

    test "shows a ticket by public_id", %{conn: conn, product: product} do
      ticket = create_ticket!(product, "Show me")

      conn = get(recycle(conn), "/api/v1/tickets/#{ticket.public_id}")

      assert json_response(conn, 200)["ticket"]["public_id"] == ticket.public_id
    end

    test "updates a ticket and returns 409 on lock conflict", %{conn: conn, product: product} do
      ticket = create_ticket!(product, "Update me")

      conn =
        patch(recycle(conn), "/api/v1/tickets/#{ticket.public_id}", %{
          ticket: %{subject: "Updated"}
        })

      assert json_response(conn, 200)["ticket"]["subject"] == "Updated"
      updated = Ash.get!(Ticket, ticket.id, domain: Helpdesk)
      assert updated.lock_version > ticket.lock_version

      conn =
        patch(recycle(conn), "/api/v1/tickets/#{ticket.public_id}", %{
          ticket: %{subject: "Stale", lock_version: ticket.lock_version}
        })

      assert json_response(conn, 409)["error"]["code"] == "conflict"
    end

    test "changes status", %{conn: conn, product: product} do
      ticket = create_ticket!(product, "Status")

      conn =
        put(recycle(conn), "/api/v1/tickets/#{ticket.public_id}/status", %{
          ticket: %{status: "triage"}
        })

      assert json_response(conn, 200)["ticket"]["status"] == "triage"

      conn =
        put(recycle(conn), "/api/v1/tickets/#{ticket.public_id}/status", %{
          ticket: %{status: "nope"}
        })

      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end

    test "external user sees only own tickets", %{
      conn: conn,
      company: company,
      product: product,
      company_code: company_code
    } do
      admin = create_user!(company.id, "admin", @password)
      _admin_ticket = create_ticket!(product, admin, "Admin ticket")
      external = create_user!(company.id, "customer", @password)
      external_ticket = create_ticket!(product, external, "Customer ticket")

      conn = log_in_with_token(recycle(conn), company_code, external)
      body = json_response(get(conn, "/api/v1/tickets"), 200)

      assert body["meta"]["total_count"] == 1
      assert hd(body["tickets"])["public_id"] == external_ticket.public_id

      admin_public_id =
        Ticket
        |> filter(requester_id == ^admin.id)
        |> Ash.read_one!(domain: Helpdesk)
        |> Map.get(:public_id)

      assert json_response(get(recycle(conn), "/api/v1/tickets/#{admin_public_id}"), 403)["error"]["code"] ==
               "forbidden"
    end

    test "another company cannot access tickets", %{conn: conn, product: product} do
      ticket = create_ticket!(product, "Mine")
      other_code = unique_company_code()
      other_company = create_company!(other_code)
      other_admin = create_user!(other_company.id, "admin", @password)

      conn = log_in_with_token(recycle(conn), other_code, other_admin)

      assert json_response(get(conn, "/api/v1/tickets/#{ticket.public_id}"), 403)["error"]["code"] ==
               "forbidden"

      assert json_response(get(recycle(conn), "/api/v1/tickets"), 200)["meta"]["total_count"] == 0
    end

    test "non-privileged user cannot change priority", %{
      conn: conn,
      company: company,
      product: product,
      company_code: company_code
    } do
      ticket = create_ticket!(product, "Priority")
      user = create_user!(company.id, "user", @password)
      conn = log_in_with_token(recycle(conn), company_code, user)

      conn =
        patch(conn, "/api/v1/tickets/#{ticket.public_id}", %{
          ticket: %{priority: "p1"}
        })

      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end

    test "lists products and public messages", %{conn: conn, product: product} do
      conn = get(recycle(conn), "/api/v1/products")
      body = json_response(conn, 200)
      assert Enum.any?(body["products"], &(&1["id"] == product.id))

      ticket = create_ticket!(product, "Messages")
      conn = get(recycle(conn), "/api/v1/tickets/#{ticket.public_id}/messages")
      assert json_response(conn, 200)["messages"] == []
    end

    test "returns 401 without a token" do
      conn = build_conn()
      assert json_response(get(conn, "/api/v1/tickets"), 401)["error"]["code"] == "unauthorized"
    end
  end

  defp sign_in(conn, company_code, login, password) do
    post(conn, "/api/v1/sign-in", %{
      company_code: company_code,
      login: to_string(login),
      password: password
    })
  end

  defp log_in_with_token(conn, company_code, user) do
    conn = sign_in(conn, company_code, user.email, @password)
    token = json_response(conn, 200)["token"]
    put_req_header(recycle(conn), "authorization", "Bearer #{token}")
  end

  defp create_ticket!(product, subject) when is_binary(subject) do
    requester = create_user!(product.company_id, "user", @password)
    create_ticket!(product, requester, subject)
  end

  defp create_ticket!(product, requester, subject) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: subject,
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company!(company_code) do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "API Company #{System.unique_integer([:positive])}",
      company_code: company_code
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role, password) do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{
        email: "api+#{role}+#{System.unique_integer([:positive])}@example.com",
        display_name: "API #{role}",
        role: role,
        status: "active",
        company_id: company_id
      })
      |> Ash.create!(domain: Accounts)

    user
    |> Ash.Changeset.for_update(:set_password, %{password: password, password_confirmation: password})
    |> Ash.update!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "API Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
