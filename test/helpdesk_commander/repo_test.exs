defmodule HelpdeskCommander.RepoTest do
  use ExUnit.Case, async: true

  test "repo defaults" do
    assert HelpdeskCommander.Repo.all_tenants() == []
    assert HelpdeskCommander.Repo.installed_extensions() == ["ash-functions"]
    refute HelpdeskCommander.Repo.prefer_transaction?()
    assert %Version{major: 16, minor: 0, patch: 0} = HelpdeskCommander.Repo.min_pg_version()
  end
end
