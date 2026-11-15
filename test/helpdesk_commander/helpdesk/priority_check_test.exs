defmodule HelpdeskCommander.Helpdesk.PriorityCheckTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.PriorityCheck
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task, as: WorkTask

  require Ash.Query

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    member = create_user!(company.id, "member")
    external = create_user!(company.id, "external")
    product = create_product!(company)

    %{company: company, admin: admin, member: member, external: external, product: product}
  end

  describe "evaluate/2" do
    test "flags critical outage keywords when priority is p3 or p4", %{
      product: product,
      admin: admin
    } do
      ticket =
        create_ticket!(product, admin, %{
          subject: "全社停止しています",
          description: "本番環境へログインできない状態です",
          type: "question",
          priority: "p3"
        })

      eval = PriorityCheck.evaluate(ticket)
      assert eval.status == :needs_review
      assert eval.needs_review?
      assert eval.suggested_priority == "p1"
      assert eval.risk_score >= 0.7
      assert Enum.any?(eval.reasons, &(&1 =~ "全社停止"))
    end

    test "flags incident ticket with low priority p4", %{product: product, admin: admin} do
      ticket =
        create_ticket!(product, admin, %{
          subject: "通知遅延の調査",
          description: "メール送信が一部遅れています",
          type: "incident",
          priority: "p4"
        })

      eval = PriorityCheck.evaluate(ticket)
      assert eval.status == :needs_review
      assert eval.suggested_priority == "p2"
    end

    test "flags all-p1 question with low-urgency wording", %{product: product, admin: admin} do
      ticket =
        create_ticket!(product, admin, %{
          subject: "管理画面の文言修正について相談",
          description: "急ぎませんのでいつでも確認したいです",
          type: "question",
          priority: "p1",
          impact: "widespread",
          urgency: "critical"
        })

      eval = PriorityCheck.evaluate(ticket)
      assert eval.status == :needs_review
      assert eval.suggested_priority == "p3"
      assert Enum.any?(eval.reasons, &(&1 =~ "低緊急度"))
    end

    test "flags p1 ticket when all open linked tasks are low priority without due date", %{
      company: company,
      product: product,
      admin: admin
    } do
      ticket =
        create_ticket!(product, admin, %{
          subject: "本番停止の復旧作業",
          description: "本番停止が発生しています",
          type: "incident",
          priority: "p1",
          impact: "widespread",
          urgency: "critical"
        })

      task = create_task!(company.id, admin, priority: "low", status: "todo")
      eval = PriorityCheck.evaluate(ticket, task_links: [%{task: task}])

      assert eval.status == :needs_review
      assert Enum.any?(eval.reasons, &(&1 =~ "関連タスク"))
    end

    test "returns :ok when priority matches content", %{product: product, admin: admin} do
      ticket =
        create_ticket!(product, admin, %{
          subject: "管理画面の使い方について質問",
          description: "CSV 出力の手順を確認したいです",
          type: "question",
          priority: "p4"
        })

      eval = PriorityCheck.evaluate(ticket)
      assert eval.status == :ok
      refute eval.needs_review?
      assert eval.reasons == []
    end
  end

  describe "accept/3 and dismiss/3" do
    test "admin can accept suggestion and update ticket priority with audit event", %{
      product: product,
      admin: admin
    } do
      ticket =
        create_ticket!(product, admin, %{
          subject: "本番停止しています",
          description: "接続できない状態です",
          type: "question",
          priority: "p4"
        })

      assert {:ok, updated} = PriorityCheck.accept(ticket, admin)
      assert updated.priority == "p1"
      assert updated.priority_source == "manual"

      events = list_events(ticket.id)
      assert Enum.any?(events, &(&1.event_type == "priority_check_accepted"))
    end

    test "member cannot accept priority change, but can dismiss false positive", %{
      product: product,
      admin: admin,
      member: member,
      external: external
    } do
      ticket =
        create_ticket!(product, admin, %{
          subject: "至急確認したい事項",
          description: "設定変更について",
          type: "question",
          priority: "p4"
        })

      assert {:error, :forbidden} = PriorityCheck.accept(ticket, member)
      assert {:error, :forbidden} = PriorityCheck.dismiss(ticket, external)

      assert {:ok, _event} = PriorityCheck.dismiss(ticket, member)
      events = list_events(ticket.id)
      eval = PriorityCheck.evaluate(ticket, events: events)

      assert eval.status == :dismissed
      assert eval.dismissed?
      refute eval.needs_review?
    end
  end

  defp list_events(ticket_id) do
    TicketEvent
    |> Ash.Query.filter(ticket_id == ^ticket_id)
    |> Ash.read!(domain: Helpdesk, authorize?: false)
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Priority Check Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_user!(company_id, role) do
    unique = System.unique_integer([:positive])

    User
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id,
      email: "pc-#{role}-#{unique}@example.com",
      display_name: "PC #{role}",
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

  defp create_ticket!(product, requester, attrs) do
    defaults = %{
      company_id: product.company_id,
      product_id: product.id,
      requester_id: requester.id,
      subject: "Default subject",
      description: "Default description",
      type: "question",
      impact: "minor",
      urgency: "low",
      priority: "p4"
    }

    Ticket
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(domain: Helpdesk, tenant: product.company_id, actor: requester)
  end

  defp create_task!(company_id, user, opts) do
    unique = System.unique_integer([:positive])

    WorkTask
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id,
      title: "Task #{unique}",
      priority: Keyword.get(opts, :priority, "low"),
      status: Keyword.get(opts, :status, "todo")
    })
    |> Ash.create!(domain: Tasks, tenant: company_id, actor: user)
  end
end
