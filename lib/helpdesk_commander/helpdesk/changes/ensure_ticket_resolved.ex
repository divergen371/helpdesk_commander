defmodule HelpdeskCommander.Helpdesk.Changes.EnsureTicketResolved do
  @moduledoc """
  対象チケットが指定ステータス（既定は `resolved`）であることを検証する Change。

  検証結果や検証日時は `resolved` のチケットにしか登録できない、といった
  リソース横断の前提条件をアクション定義から切り離すために使う。
  """

  use Ash.Resource.Change

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @opt_schema [
    ticket_id_attribute: [
      type: :atom,
      default: :ticket_id,
      doc: "チケット ID を保持する属性"
    ],
    required_status: [
      type: :string,
      default: "resolved",
      doc: "チケットに要求するステータス"
    ]
  ]

  @spec opt_schema() :: Keyword.t()
  def opt_schema, do: @opt_schema

  opt_schema = @opt_schema

  defmodule Opts do
    @moduledoc false
    use Spark.Options.Validator, schema: opt_schema
  end

  @impl Ash.Resource.Change
  def init(opts) do
    case Opts.validate(opts) do
      {:ok, validated} -> {:ok, Opts.to_options(validated)}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @impl Ash.Resource.Change
  def change(changeset, opts, _context) do
    ticket_id_attribute = opts[:ticket_id_attribute]

    case Ash.Changeset.get_attribute(changeset, ticket_id_attribute) do
      nil ->
        changeset

      ticket_id ->
        ensure_resolved(changeset, ticket_id, ticket_id_attribute, opts[:required_status])
    end
  end

  defp ensure_resolved(changeset, ticket_id, ticket_id_attribute, required_status) do
    case Ash.get(Ticket, %{id: ticket_id}, domain: Helpdesk) do
      {:ok, %Ticket{status: ^required_status}} ->
        changeset

      {:ok, %Ticket{status: _status}} ->
        Ash.Changeset.add_error(changeset,
          field: ticket_id_attribute,
          message: "#{required_status}以外のチケットは検証できません"
        )

      _result ->
        Ash.Changeset.add_error(changeset,
          field: ticket_id_attribute,
          message: "チケットが見つかりません"
        )
    end
  end
end
