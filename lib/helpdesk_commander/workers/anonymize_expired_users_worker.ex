defmodule HelpdeskCommander.Workers.AnonymizeExpiredUsersWorker do
  @moduledoc """
  30日以上 suspended 状態のユーザーを自動的に匿名化する。
  日次 cron で実行される。
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @grace_period_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@grace_period_days, :day)

    case fetch_expired_suspended_users(cutoff) do
      {:ok, []} ->
        :ok

      {:ok, users} ->
        anonymize_users(users)

      {:error, error} ->
        ErrorLog.log_error("workers.anonymize_expired_users.fetch", error)
        {:error, error}
    end
  end

  defp fetch_expired_suspended_users(cutoff) do
    User
    |> filter(status == "suspended" and suspended_at <= ^cutoff)
    |> Ash.read(domain: Accounts)
  end

  defp anonymize_users(users) do
    results =
      Enum.map(users, fn user ->
        case user
             |> Ash.Changeset.for_update(:anonymize, %{})
             |> Ash.update(domain: Accounts) do
          {:ok, _anonymized} ->
            :ok

          {:error, error} ->
            ErrorLog.log_error("workers.anonymize_expired_users.anonymize", error, user_id: user.id)

            {:error, user.id}
        end
      end)

    failures = Enum.filter(results, &match?({:error, _id}, &1))

    if failures == [] do
      :ok
    else
      {:error, {:partial_failure, length(failures), length(users)}}
    end
  end
end
