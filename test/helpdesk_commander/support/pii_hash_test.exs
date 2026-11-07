defmodule HelpdeskCommander.Support.PiiHashTest do
  use ExUnit.Case, async: true

  alias HelpdeskCommander.Support.PiiHash

  test "normalize trims and downcases" do
    assert PiiHash.normalize("  Foo@Example.COM \n") == "foo@example.com"
    assert PiiHash.normalize("already") == "already"
    assert PiiHash.normalize("") == ""
  end

  test "email hashes the normalized value" do
    assert PiiHash.email("  Foo@Example.COM ") == PiiHash.email("foo@example.com")
    refute PiiHash.email("foo@example.com") == PiiHash.email("bar@example.com")
  end

  test "company_name trims but preserves case" do
    assert PiiHash.company_name("  Acme  ") == PiiHash.company_name("Acme")
    refute PiiHash.company_name("Acme") == PiiHash.company_name("acme")
  end
end
