defmodule HelpdeskCommander.Accounts do
  @moduledoc false

  use Ash.Domain

  resources do
    resource HelpdeskCommander.Accounts.Company
    resource HelpdeskCommander.Accounts.User
  end
end
