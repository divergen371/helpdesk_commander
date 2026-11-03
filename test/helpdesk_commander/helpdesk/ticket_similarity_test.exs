defmodule HelpdeskCommander.Helpdesk.TicketSimilarityTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketLink
  alias HelpdeskCommander.Helpdesk.TicketSimilarity

  describe "text_similarity/4" do
    test "scores near-duplicate Japanese tickets highly" do
      score =
        TicketSimilarity.text_similarity(
          "ログインできない",
          "ログイン時に500エラーが発生する",
          "ログインできない",
          "ログインすると500エラーになる"
        )

      assert score >= 0.6
    end

    test "scores unrelated tickets low" do
      score =
        TicketSimilarity.text_similarity(
          "ログインできない",
          "ログイン時に500エラーが発生する",
          "請求書の出力が遅い",
          "請求書PDFの生成に時間がかかる"
        )

      assert score < 0.3
    end

    test "handles empty text" do
      assert TicketSimilarity.text_similarity("", "", "", "") == 0.0
    end
  end

  describe "suggest/2" do
    test "returns similar tickets in the same company and excludes unrelated ones" do
      company = create_company!()
      user = create_user!(company.id)
      product = create_product!(company)

      target =
        create_ticket!(product, user, %{
          subject: "ログインできない",
          description: "ログイン時に500エラーが発生する"
        })

      similar =
        create_ticket!(product, user, %{
          subject: "ログインできない",
          description: "ログインすると500エラーになる"
        })

      _unrelated =
        create_ticket!(product, user, %{
          subject: "請求書の出力が遅い",
          description: "請求書PDFの生成に時間がかかる"
        })

      other_company = create_company!()
      other_user = create_user!(other_company.id)
      other_product = create_product!(other_company)
      _other_ticket = create_ticket!(other_product, other_user, %{subject: "ログインできない"})

      assert {:ok, suggestions} = TicketSimilarity.suggest(target)

      assert Enum.map(suggestions, & &1.ticket.id) == [similar.id]
      assert hd(suggestions).score >= 0.3

      assert {:ok, []} = Ash.read(TicketLink, domain: Helpdesk)
    end

    test "respects threshold and limit" do
      company = create_company!()
      user = create_user!(company.id)
      product = create_product!(company)

      target = create_ticket!(product, user, %{subject: "VPN接続が切れる"})

      for index <- 1..3 do
        create_ticket!(product, user, %{
          subject: "VPN接続が切れる #{index}",
          description: "VPNが1時間ごとに切断される"
        })
      end

      assert {:ok, suggestions} = TicketSimilarity.suggest(target, limit: 2)
      assert length(suggestions) == 2

      assert {:ok, []} = TicketSimilarity.suggest(target, threshold: 0.99)
    end

    test "returns an empty list when the ticket has no text signal" do
      company = create_company!()
      user = create_user!(company.id)
      product = create_product!(company)

      target = create_ticket!(product, user, %{subject: "あ"})
      _candidate = create_ticket!(product, user, %{subject: "い"})

      assert {:ok, []} = TicketSimilarity.suggest(target)
    end
  end

  defp create_ticket!(product, requester, attrs) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: Map.get(attrs, :subject, "Ticket"),
      description: Map.get(attrs, :description),
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Similarity Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "similarity+#{System.unique_integer([:positive])}@example.com",
      display_name: "Similarity User",
      role: "user",
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Similarity Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
