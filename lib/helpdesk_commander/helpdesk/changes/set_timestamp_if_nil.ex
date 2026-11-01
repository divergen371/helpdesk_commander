defmodule HelpdeskCommander.Helpdesk.Changes.SetTimestampIfNil do
  @moduledoc """
  指定した日時属性が未設定のとき、現在時刻で補完する Change。

  `when_status` を指定すると、`:status` 引数がその値で、かつ現在のステータスと
  異なるときだけ補完する。ステータス遷移に伴う日時の記録に使う。
  """

  use Ash.Resource.Change

  @opt_schema [
    attribute: [
      type: :atom,
      required: true,
      doc: "補完する日時属性"
    ],
    when_status: [
      type: :string,
      doc: "このステータスへ遷移するときだけ補完する"
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
    if applies?(changeset, opts[:when_status]) do
      set_if_nil(changeset, opts[:attribute])
    else
      changeset
    end
  end

  @doc """
  属性が未設定の場合だけ現在時刻を設定する。
  """
  @spec set_if_nil(Ash.Changeset.t(), atom()) :: Ash.Changeset.t()
  def set_if_nil(changeset, attribute) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil -> Ash.Changeset.change_attribute(changeset, attribute, DateTime.utc_now())
      _value -> changeset
    end
  end

  defp applies?(_changeset, nil), do: true

  defp applies?(changeset, status) do
    Ash.Changeset.get_argument(changeset, :status) == status and
      Map.get(changeset.data, :status) != status
  end
end
