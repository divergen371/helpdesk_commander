defmodule HelpdeskCommander.Helpdesk.TicketNotification do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias HelpdeskCommander.Helpdesk.TicketNotification.Preparations.ForRecipient

  postgres do
    table "ticket_notifications"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :notification_type, :string, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true
    attribute :meta, :map, allow_nil?: false, default: %{}, public?: true
    attribute :read_at, :utc_datetime_usec, public?: true

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

    belongs_to :recipient, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :actor, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end
  end

  preparations do
    prepare ForRecipient
    prepare build(sort: [inserted_at: :desc])
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(recipient_id == ^actor(:id))
    end

    policy action(:mark_read) do
      authorize_if expr(recipient_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :notification_type,
        :title,
        :body,
        :meta,
        :company_id,
        :ticket_id,
        :recipient_id,
        :actor_id
      ]
    end

    update :mark_read do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :read_at, DateTime.utc_now())
      end
    end
  end
end
