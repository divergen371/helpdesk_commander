defmodule HelpdeskCommander.Accounts.PiiEncryptionTest do
  use HelpdeskCommander.DataCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Inquiry
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Repo
  alias HelpdeskCommander.Support.PiiHash

  test "email is encrypted at rest and readable through the resource" do
    company = create_company!()
    user = create_user!(company, "plain@example.com")

    assert user.email == "plain@example.com"
    assert user.email_hash == PiiHash.email("plain@example.com")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_email FROM users WHERE id = $1", [user.id])

    refute stored =~ "plain@example.com"

    assert HelpdeskCommander.Vault.decrypt!(Base.decode64!(stored)) ==
             :erlang.term_to_binary("plain@example.com")
  end

  test "company name is encrypted at rest and readable through the resource" do
    company = create_company!("Encrypted Co")

    assert company.name == "Encrypted Co"
    assert company.name_hash == PiiHash.company_name("Encrypted Co")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_name FROM companies WHERE id = $1", [company.id])

    refute stored =~ "Encrypted Co"
  end

  test "email uniqueness uses the hash within a company" do
    company = create_company!()
    create_user!(company, "dup@example.com")

    assert {:error, _error} = create_user(company, "DUP@example.com")

    other_company = create_company!()
    assert {:ok, _user} = create_user(other_company, "dup@example.com")
  end

  test "company name uniqueness uses the hash" do
    _company = create_company!("Unique Co")

    assert {:error, _error} =
             Company
             |> Ash.Changeset.for_create(:create, %{
               name: " Unique Co ",
               company_code: unique_company_code()
             })
             |> Ash.create(domain: Accounts)
  end

  test "display_name is encrypted at rest" do
    company = create_company!()
    user = create_user!(company, "named@example.com")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_display_name FROM users WHERE id = $1", [user.id])

    refute stored =~ "named@example.com"
    assert user.display_name == "named@example.com"
  end

  test "ticket description is encrypted at rest" do
    company = create_company!()
    user = create_user!(company, "ticket@example.com")
    ticket = create_ticket!(user, "秘密の詳細")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_description FROM tickets WHERE id = $1", [ticket.id])

    refute stored =~ "秘密の詳細"
    assert ticket.description == "秘密の詳細"
  end

  test "nil ticket description stays NULL" do
    company = create_company!()
    user = create_user!(company, "null@example.com")
    ticket = create_ticket!(user, nil)

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_description FROM tickets WHERE id = $1", [ticket.id])

    assert stored == nil
    assert ticket.description == nil
  end

  test "inquiry body is encrypted at rest" do
    company = create_company!()
    user = create_user!(company, "inquiry@example.com")
    product = create_product!(company)

    inquiry =
      Inquiry
      |> Ash.Changeset.for_create(:create, %{
        subject: "質問",
        body: "本文の秘密",
        product_id: product.id,
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_body FROM inquiries WHERE id = $1", [inquiry.id])

    refute stored =~ "本文の秘密"
    assert inquiry.body == "本文の秘密"
  end

  test "conversation message body is encrypted at rest" do
    company = create_company!()
    user = create_user!(company, "chat@example.com")
    ticket = create_ticket!(user, nil)
    conversation = fetch_conversation!(ticket)
    message = create_message!(conversation, user, "チャットの秘密")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_body FROM conversation_messages WHERE id = $1", [message.id])

    refute stored =~ "チャットの秘密"
    assert message.body == "チャットの秘密"
  end

  test "anonymize replaces the email and keeps the hash consistent" do
    company = create_company!()
    user = create_user!(company, "removed@example.com")

    anonymized =
      user
      |> Ash.Changeset.for_update(:anonymize, %{})
      |> Ash.update!(domain: Accounts)

    assert anonymized.email == "deleted-#{user.id}@anonymized.local"
    assert anonymized.email_hash == PiiHash.email(anonymized.email)
  end

  defp create_user!(company, email) do
    {:ok, user} = create_user(company, email)
    user
  end

  defp create_user(company, email) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: email,
      status: "active",
      company_id: company.id
    })
    |> Ash.create(domain: Accounts)
  end

  defp create_product!(%Company{id: company_id}), do: create_product!(company_id)

  defp create_product!(company_id) when is_integer(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_ticket!(user, description) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Ticket",
      description: description,
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp fetch_conversation!(ticket) do
    Conversation
    |> filter(ticket_id == ^ticket.id and kind == "internal_public")
    |> Ash.read_one!(domain: Helpdesk)
  end

  defp create_message!(conversation, user, body) do
    ConversationMessage
    |> Ash.Changeset.for_create(:create, %{
      conversation_id: conversation.id,
      sender_id: user.id,
      body: body
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company!(name \\ nil) do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: name || "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
