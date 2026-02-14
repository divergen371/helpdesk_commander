defmodule HelpdeskCommander.Helpdesk.TicketVerification do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Workers.CreateTicketNotificationsWorker

  @result_regex ~r/^(passed|failed|needs_review)$/

  postgres do
    table "ticket_verifications"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :result, :string,
      allow_nil?: false,
      constraints: [match: @result_regex],
      public?: true

    attribute :notes, :string, public?: true
    attribute :verified_at, :utc_datetime_usec, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :ticket, HelpdeskCommander.Helpdesk.Ticket do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :verifier, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:ticket_id, :verifier_id, :result, :notes, :verified_at, :company_id]

      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromTicket

      change fn changeset, _context ->
        ticket_id =
          Ash.Changeset.get_attribute(changeset, :ticket_id) ||
            Ash.Changeset.get_argument(changeset, :ticket_id)

        case ticket_id do
          nil ->
            changeset

          id ->
            case Ash.get(Ticket, %{id: id}, domain: HelpdeskCommander.Helpdesk) do
              {:ok, %Ticket{status: "resolved"}} ->
                changeset

              {:ok, %Ticket{status: _status}} ->
                Ash.Changeset.add_error(changeset,
                  field: :ticket_id,
                  message: "resolved以外のチケットは検証できません"
                )

              _result ->
                Ash.Changeset.add_error(changeset,
                  field: :ticket_id,
                  message: "チケットが見つかりません"
                )
            end
        end
      end

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :verified_at) do
          nil -> Ash.Changeset.change_attribute(changeset, :verified_at, DateTime.utc_now())
          _value -> changeset
        end
      end

      change after_action(fn _changeset, verification, _context ->
               ticket = Ash.get!(Ticket, %{id: verification.ticket_id}, domain: HelpdeskCommander.Helpdesk)

               _event =
                 TicketEvent
                 |> Ash.Changeset.for_create(:create, %{
                   event_type: "verification_submitted",
                   data: %{result: verification.result},
                   ticket_id: verification.ticket_id,
                   actor_id: verification.verifier_id,
                   company_id: verification.company_id
                 })
                 |> Ash.create!(domain: HelpdeskCommander.Helpdesk)

               _job =
                 CreateTicketNotificationsWorker.enqueue(%{
                   notification_type: "ticket_verification_submitted",
                   title: "検証結果が登録されました",
                   body: "Ticket #{ticket.public_id} に検証結果（#{verification.result}）が登録されました。",
                   company_id: verification.company_id,
                   ticket_id: verification.ticket_id,
                   actor_id: verification.verifier_id,
                   meta: %{result: verification.result}
                 })

               {:ok, verification}
             end)
    end
  end
end
