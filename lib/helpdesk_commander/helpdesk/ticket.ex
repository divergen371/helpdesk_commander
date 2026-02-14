defmodule HelpdeskCommander.Helpdesk.Ticket do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Support.PublicId
  alias HelpdeskCommander.Workers.CreateTicketNotificationsWorker

  @status_regex ~r/^(new|triage|in_progress|waiting|resolved|verified|closed)$/

  @status_transitions %{
    "new" => ~w(triage in_progress waiting resolved),
    "triage" => ~w(in_progress waiting resolved),
    "in_progress" => ~w(waiting resolved),
    "waiting" => ~w(in_progress resolved),
    "resolved" => ~w(in_progress waiting verified closed),
    "verified" => [],
    "closed" => []
  }

  postgres do
    table "tickets"
    repo HelpdeskCommander.Repo
    migration_types public_id: {:string, 32}
  end

  defp create_conversation(ticket, actor_id, kind) do
    Conversation
    |> Ash.Changeset.for_create(:create, %{
      ticket_id: ticket.id,
      kind: kind,
      created_by_id: actor_id,
      company_id: ticket.company_id
    })
    |> Ash.create!(domain: HelpdeskCommander.Helpdesk)
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :public_id, :string,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [max_length: 32],
      default: &PublicId.generate/0

    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :description, :string
    attribute :type, :string, allow_nil?: false, default: "question"

    attribute :status, :string,
      allow_nil?: false,
      default: "new",
      constraints: [match: @status_regex]

    attribute :priority, :string, allow_nil?: false, default: "p3"

    attribute :visibility_scope, :string,
      allow_nil?: false,
      default: "company",
      constraints: [match: ~r/^(company|global_pending|global)$/]

    attribute :visibility_decided_at, :utc_datetime_usec
    attribute :impact, :string
    attribute :urgency, :string
    attribute :first_response_at, :utc_datetime_usec
    attribute :resolved_at, :utc_datetime_usec
    attribute :verified_at, :utc_datetime_usec
    attribute :closed_at, :utc_datetime_usec
    attribute :latest_message_at, :utc_datetime_usec
    attribute :lock_version, :integer, allow_nil?: false, default: 1

    timestamps()
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

    belongs_to :assignee, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end

    belongs_to :visibility_decided_by, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end

    has_many :conversations, HelpdeskCommander.Helpdesk.Conversation do
      destination_attribute :ticket_id
      public? true
    end

    has_many :events, HelpdeskCommander.Helpdesk.TicketEvent do
      destination_attribute :ticket_id
      public? true
    end

    has_many :verifications, HelpdeskCommander.Helpdesk.TicketVerification do
      destination_attribute :ticket_id
      public? true
    end

    has_many :outgoing_links, HelpdeskCommander.Helpdesk.TicketLink do
      destination_attribute :ticket_id
      public? true
    end

    has_many :incoming_links, HelpdeskCommander.Helpdesk.TicketLink do
      destination_attribute :related_ticket_id
      public? true
    end
  end

  identities do
    identity :unique_public_id, [:public_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :company_id,
        :product_id,
        :subject,
        :description,
        :type,
        :status,
        :priority,
        :visibility_scope,
        :visibility_decided_by_id,
        :visibility_decided_at,
        :impact,
        :urgency,
        :requester_id,
        :assignee_id
      ]

      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromRequester

      change after_action(fn changeset, ticket, _context ->
               actor_id =
                 Ash.Changeset.get_attribute(changeset, :requester_id) || ticket.requester_id

               _public = ensure_conversation(ticket, actor_id, "internal_public")
               _private = ensure_conversation(ticket, actor_id, "internal_private")

               _event =
                 TicketEvent
                 |> Ash.Changeset.for_create(:create, %{
                   event_type: "ticket_created",
                   data: %{},
                   ticket_id: ticket.id,
                   actor_id: actor_id,
                   company_id: ticket.company_id
                 })
                 |> Ash.create!(domain: HelpdeskCommander.Helpdesk)

               {:ok, ticket}
             end)
    end

    update :update do
      require_atomic? false

      argument :actor_id, HelpdeskCommander.Types.BigInt, allow_nil?: true

      accept [
        :company_id,
        :product_id,
        :subject,
        :description,
        :type,
        :priority,
        :visibility_scope,
        :visibility_decided_by_id,
        :visibility_decided_at,
        :impact,
        :urgency,
        :first_response_at,
        :resolved_at,
        :verified_at,
        :closed_at,
        :latest_message_at,
        :requester_id,
        :assignee_id
      ]

      change fn changeset, context ->
        enforce_privileged_update_permissions(changeset, context)
      end

      change optimistic_lock(:lock_version)
    end

    update :set_status do
      require_atomic? false

      argument :status, :string, allow_nil?: false
      argument :actor_id, HelpdeskCommander.Types.BigInt, allow_nil?: false

      change fn changeset, context ->
        apply_status_transition(changeset, context)
      end

      change optimistic_lock(:lock_version)

      change after_action(fn changeset, ticket, _context ->
               previous = changeset.data
               from_status = previous.status
               to_status = ticket.status

               if from_status != to_status do
                 data =
                   maybe_add_rollback_data(
                     %{
                       from: from_status,
                       to: to_status
                     },
                     from_status,
                     to_status
                   )

                 _event =
                   TicketEvent
                   |> Ash.Changeset.for_create(:create, %{
                     event_type: "status_changed",
                     data: data,
                     ticket_id: ticket.id,
                     actor_id: Ash.Changeset.get_argument(changeset, :actor_id),
                     company_id: ticket.company_id
                   })
                   |> Ash.create!(domain: HelpdeskCommander.Helpdesk)

                 if to_status == "resolved" do
                   _job =
                     CreateTicketNotificationsWorker.enqueue(%{
                       notification_type: "ticket_resolved_review_required",
                       title: "検証待ちチケット",
                       body: "Ticket #{ticket.public_id} が resolved になりました。検証/承認を確認してください。",
                       company_id: ticket.company_id,
                       ticket_id: ticket.id,
                       actor_id: Ash.Changeset.get_argument(changeset, :actor_id),
                       meta: %{from: from_status, to: to_status}
                     })
                 end
               end

               {:ok, ticket}
             end)

      accept []
    end
  end

  defp ensure_conversation(ticket, actor_id, kind) do
    conversation_result =
      Conversation
      |> filter(ticket_id == ^ticket.id and kind == ^kind)
      |> Ash.read_one(domain: HelpdeskCommander.Helpdesk)

    case conversation_result do
      {:ok, nil} ->
        create_conversation(ticket, actor_id, kind)

      {:ok, conversation} ->
        conversation

      _result ->
        create_conversation(ticket, actor_id, kind)
    end
  end

  defp apply_status_transition(changeset, context) do
    from_status = changeset.data.status
    to_status = Ash.Changeset.get_argument(changeset, :status)

    cond do
      is_nil(to_status) ->
        changeset

      from_status == to_status ->
        changeset

      allowed_status_transition?(from_status, to_status) and status_requires_privileged_role?(to_status) ->
        case fetch_actor(changeset, context) do
          {:ok, %User{} = actor} ->
            if privileged_role?(actor) do
              changeset
              |> Ash.Changeset.change_attribute(:status, to_status)
              |> maybe_set_status_timestamps(from_status, to_status)
            else
              add_privileged_role_error(changeset, "このステータスへの遷移は管理者/リーダーのみ可能です")
            end

          _result ->
            add_privileged_role_error(changeset, "権限判定に必要な操作ユーザー情報が不足しています")
        end

      allowed_status_transition?(from_status, to_status) ->
        changeset
        |> Ash.Changeset.change_attribute(:status, to_status)
        |> maybe_set_status_timestamps(from_status, to_status)

      true ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "ステータス遷移が許可されていません"
        )
    end
  end

  defp allowed_status_transition?(from_status, to_status) do
    allowed = Map.get(@status_transitions, from_status, [])
    to_status in allowed
  end

  defp maybe_set_status_timestamps(changeset, _from_status, "in_progress") do
    maybe_set_timestamp(changeset, :first_response_at)
  end

  defp maybe_set_status_timestamps(changeset, _from_status, "resolved") do
    maybe_set_timestamp(changeset, :resolved_at)
  end

  defp maybe_set_status_timestamps(changeset, _from_status, "verified") do
    maybe_set_timestamp(changeset, :verified_at)
  end

  defp maybe_set_status_timestamps(changeset, _from_status, "closed") do
    maybe_set_timestamp(changeset, :closed_at)
  end

  defp maybe_set_status_timestamps(changeset, _from_status, _to_status), do: changeset

  defp enforce_privileged_update_permissions(changeset, context) do
    if privileged_update?(changeset) do
      case fetch_actor(changeset, context) do
        {:ok, %User{} = actor} ->
          if privileged_role?(actor) do
            changeset
          else
            add_privileged_role_error(changeset, "優先度・担当者の確定は管理者/リーダーのみ可能です")
          end

        _result ->
          add_privileged_role_error(changeset, "権限判定に必要な操作ユーザー情報が不足しています")
      end
    else
      changeset
    end
  end

  defp privileged_update?(changeset) do
    attribute_changed?(changeset, :priority) or attribute_changed?(changeset, :assignee_id)
  end

  defp attribute_changed?(changeset, field) do
    Ash.Changeset.get_attribute(changeset, field) != Map.get(changeset.data, field)
  end

  defp status_requires_privileged_role?(status), do: status in ~w(verified closed)

  defp fetch_actor(changeset, context) do
    actor_id = Ash.Changeset.get_argument(changeset, :actor_id) || actor_id_from_context(context)

    case actor_id do
      nil -> {:error, :missing_actor}
      id -> Ash.get(User, %{id: id}, domain: Accounts)
    end
  end

  defp actor_id_from_context(%{actor: %User{id: id}}), do: id
  defp actor_id_from_context(%{actor: %{id: id}}) when is_integer(id), do: id
  defp actor_id_from_context(_context), do: nil
  defp privileged_role?(%User{role: role}), do: role in ~w(admin leader)

  defp add_privileged_role_error(changeset, message) do
    Ash.Changeset.add_error(changeset,
      field: :actor_id,
      message: message
    )
  end

  defp maybe_set_timestamp(changeset, field) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil -> Ash.Changeset.change_attribute(changeset, field, DateTime.utc_now())
      _value -> changeset
    end
  end

  defp maybe_add_rollback_data(data, "resolved", to_status) when to_status != "resolved" do
    Map.put(data, :rolled_back_at, DateTime.utc_now())
  end

  defp maybe_add_rollback_data(data, _from_status, _to_status), do: data
end
