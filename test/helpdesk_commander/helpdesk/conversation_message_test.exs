defmodule HelpdeskCommander.Helpdesk.ConversationMessageTest do
  use HelpdeskCommander.DataCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "edit updates the body, type, and edited timestamp" do
    {_ticket, _conversation, message} = create_message!("Original")

    edited =
      message
      |> Ash.Changeset.for_update(:edit, %{body: "Updated", message_type: "note"})
      |> Ash.update!(domain: Helpdesk)

    assert edited.body == "Updated"
    assert edited.message_type == "note"
    assert edited.edited_at != nil
    assert edited.deleted_at == nil
  end

  test "soft_delete scrubs the body and metadata" do
    {_ticket, _conversation, message} = create_message!("Secret body")

    deleted =
      message
      |> Ash.Changeset.for_update(:soft_delete, %{})
      |> Ash.update!(domain: Helpdesk)

    assert deleted.deleted_at != nil
    assert deleted.body == ""
    assert deleted.meta == %{}
  end

  test "message_type is restricted to known values" do
    {_ticket, _conversation, message} = create_message!("Typed")

    assert {:error, _error} =
             message
             |> Ash.Changeset.for_update(:edit, %{message_type: "unknown"})
             |> Ash.update(domain: Helpdesk)
  end

  defp create_message!(body) do
    company = Accounts.Auth.default_company!()

    user =
      User
      |> Ash.Changeset.for_create(:create, %{
        email: "message+#{System.unique_integer([:positive])}@example.com",
        display_name: "Message User",
        status: "active",
        company_id: company.id
      })
      |> Ash.create!(domain: Accounts)

    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Message Product #{System.unique_integer([:positive])}",
        company_id: company.id
      })
      |> Ash.create!(domain: Helpdesk)

    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        subject: "Message Ticket",
        product_id: product.id,
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    conversation =
      Conversation
      |> filter(ticket_id == ^ticket.id and kind == "internal_public")
      |> Ash.read_one!(domain: Helpdesk)

    message =
      ConversationMessage
      |> Ash.Changeset.for_create(:create, %{
        body: body,
        conversation_id: conversation.id,
        sender_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    {ticket, conversation, message}
  end
end
