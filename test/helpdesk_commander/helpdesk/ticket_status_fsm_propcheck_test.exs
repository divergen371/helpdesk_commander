defmodule HelpdeskCommander.Helpdesk.TicketStatusFsmPropCheckTest do
  use HelpdeskCommander.DataCase, async: true
  use PropCheck.FSM

  @moduletag store_counter_example: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  @status_transitions %{
    new: [:triage, :in_progress, :waiting, :resolved],
    triage: [:in_progress, :waiting, :resolved],
    in_progress: [:waiting, :resolved],
    waiting: [:in_progress, :resolved],
    resolved: [:in_progress, :waiting, :verified, :closed],
    verified: [],
    closed: []
  }

  @status_functions %{
    triage: :set_status_triage,
    in_progress: :set_status_in_progress,
    waiting: :set_status_waiting,
    resolved: :set_status_resolved,
    verified: :set_status_verified,
    closed: :set_status_closed
  }

  property "propcheck: ticket status transitions follow FSM", numtests: 15, max_size: 20 do
    forall cmds <- PropCheck.FSM.commands(__MODULE__) do
      {history, state, result} = PropCheck.FSM.run_commands(__MODULE__, cmds)

      (result == :ok)
      |> when_fail(
        IO.inspect(
          %{cmds: cmds, history: history, state: state, result: result},
          label: "fsm_failure_details"
        )
      )
    end
  end

  defp history_noop(_data) do
    {:history, {:call, __MODULE__, :noop, []}}
  end

  @impl true
  def initial_state, do: :uninitialized

  @impl true
  def initial_state_data, do: %{ticket_info: nil}

  def uninitialized(_data) do
    [{:new, {:call, __MODULE__, :create_ticket, []}}]
  end

  def new(data), do: build_transitions(data, @status_transitions[:new])
  def triage(data), do: build_transitions(data, @status_transitions[:triage])
  def in_progress(data), do: build_transitions(data, @status_transitions[:in_progress])
  def waiting(data), do: build_transitions(data, @status_transitions[:waiting])
  def resolved(data), do: build_transitions(data, @status_transitions[:resolved])
  def verified(data), do: [history_noop(data)]
  def closed(data), do: [history_noop(data)]

  @impl true
  def precondition(_from, _target, _data, _call), do: true

  @impl true
  def postcondition(:uninitialized, :new, _data, {:call, __MODULE__, :create_ticket, []}, result) do
    match?(
      {ticket_id, user_id, admin_id} when is_integer(ticket_id) and is_integer(user_id) and is_integer(admin_id),
      result
    )
  end

  def postcondition(_from, _target, _data, {:call, __MODULE__, :noop, []}, result) do
    result == :ok
  end

  def postcondition(_from, target, _data, {:call, __MODULE__, function, [_ticket_info]}, result)
      when function in [
             :set_status_triage,
             :set_status_in_progress,
             :set_status_waiting,
             :set_status_resolved,
             :set_status_verified,
             :set_status_closed
           ] do
    status = Atom.to_string(target)

    case result do
      {:ok, %Ticket{} = ticket} ->
        ticket.status == status and timestamp_ok?(status, ticket)

      _result ->
        false
    end
  end

  @impl true
  def next_state_data(:uninitialized, :new, _data, result, {:call, __MODULE__, :create_ticket, []}) do
    %{ticket_info: result}
  end

  def next_state_data(_from, _target, data, _result, _call), do: data

  def create_ticket do
    company = Accounts.Auth.default_company!()
    user = create_user!(company.id, "user")
    admin = create_user!(company.id, "admin")
    product = create_product!(company.id)

    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        subject: "PropCheck Ticket",
        description: "PropCheck Ticket",
        product_id: product.id,
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    {ticket.id, user.id, admin.id}
  end

  def set_status(ticket_id, status, actor_id) do
    Ticket
    |> Ash.get!(%{id: ticket_id}, domain: Helpdesk)
    |> Ash.Changeset.for_update(:set_status, %{status: status, actor_id: actor_id})
    |> Ash.update(domain: Helpdesk)
  end

  def set_status_triage({ticket_id, user_id, _admin_id}), do: set_status(ticket_id, "triage", user_id)
  def set_status_triage(_), do: {:error, :symbolic}
  def set_status_in_progress({ticket_id, user_id, _admin_id}), do: set_status(ticket_id, "in_progress", user_id)
  def set_status_in_progress(_), do: {:error, :symbolic}
  def set_status_waiting({ticket_id, user_id, _admin_id}), do: set_status(ticket_id, "waiting", user_id)
  def set_status_waiting(_), do: {:error, :symbolic}
  def set_status_resolved({ticket_id, user_id, _admin_id}), do: set_status(ticket_id, "resolved", user_id)
  def set_status_resolved(_), do: {:error, :symbolic}
  def set_status_verified({ticket_id, _user_id, admin_id}), do: set_status(ticket_id, "verified", admin_id)
  def set_status_verified(_), do: {:error, :symbolic}
  def set_status_closed({ticket_id, _user_id, admin_id}), do: set_status(ticket_id, "closed", admin_id)
  def set_status_closed(_), do: {:error, :symbolic}

  def noop, do: :ok

  defp build_transitions(data, targets) do
    Enum.map(targets, fn target ->
      function = Map.fetch!(@status_functions, target)
      {target, {:call, __MODULE__, function, [data.ticket_info]}}
    end)
  end

  defp timestamp_ok?("in_progress", %Ticket{first_response_at: value}), do: value != nil
  defp timestamp_ok?("resolved", %Ticket{resolved_at: value}), do: value != nil
  defp timestamp_ok?("verified", %Ticket{verified_at: value}), do: value != nil
  defp timestamp_ok?("closed", %Ticket{closed_at: value}), do: value != nil
  defp timestamp_ok?(_status, %Ticket{}), do: true

  defp create_user!(company_id, role) do
    email = "propcheck+#{role}+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "PropCheck #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
