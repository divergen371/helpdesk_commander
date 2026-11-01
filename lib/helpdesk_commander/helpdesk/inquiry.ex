defmodule HelpdeskCommander.Helpdesk.Inquiry do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  alias HelpdeskCommander.Helpdesk.Inquiry.Changes.CreateTicket

  postgres do
    table "inquiries"
    repo HelpdeskCommander.Repo
  end

  cloak do
    vault(HelpdeskCommander.Vault)
    attributes([:body])
    decrypt_by_default([:body])
  end

  multitenancy do
    strategy :attribute
    attribute :company_id
    global? true
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :subject, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 200]

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 10_000]

    attribute :source, :string, allow_nil?: false, default: "web", public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :product, HelpdeskCommander.Helpdesk.Product do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :requester, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :ticket, HelpdeskCommander.Helpdesk.Ticket do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  code_interface do
    define :create_inquiry, action: :create
  end

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  actions do
    defaults [:read]

    create :create do
      accept [:subject, :body, :source, :requester_id, :product_id]

      change HelpdeskCommander.Helpdesk.Inquiry.Changes.NormalizeFields
      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromRequester
      change HelpdeskCommander.Helpdesk.Inquiry.Changes.ValidateTenant

      change CreateTicket
    end
  end
end
