defmodule HelpdeskCommander.Helpdesk.ReportSchedule do
  @moduledoc """
  レポート・統計の定期配信スケジュール（HC-29）。

  会社ごとに配信周期（日次/週次）・チャネル（email / chat）・宛先を保持し、
  Oban の Cron から起動されるワーカーが Analytics の要約を帳票化して配信する。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "report_schedules"
    repo HelpdeskCommander.Repo

    references do
      reference :company, on_delete: :delete
    end
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

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :period, :string, allow_nil?: false, default: "daily", public?: true
    attribute :channel, :string, allow_nil?: false, default: "email", public?: true
    attribute :recipients, :string, allow_nil?: true, default: "", public?: true
    attribute :enabled, :boolean, allow_nil?: false, default: true, public?: true
    attribute :last_sent_at, :utc_datetime_usec, public?: true
    attribute :last_failed_at, :utc_datetime_usec, public?: true
    attribute :last_error, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :period, :channel, :recipients, :enabled]

      validate one_of(:period, ["daily", "weekly"])
      validate one_of(:channel, ["email", "chat"])
      validate attribute_does_not_equal(:name, "")
    end

    update :update do
      require_atomic? false
      accept [:name, :period, :channel, :recipients, :enabled]

      validate one_of(:period, ["daily", "weekly"])
      validate one_of(:channel, ["email", "chat"])
      validate attribute_does_not_equal(:name, "")
    end

    update :mark_sent do
      require_atomic? false
      accept []
      change set_attribute(:last_sent_at, &DateTime.utc_now/0)
      change set_attribute(:last_error, nil)
    end

    update :mark_failed do
      require_atomic? false
      accept [:last_error]
      change set_attribute(:last_failed_at, &DateTime.utc_now/0)
    end
  end
end
