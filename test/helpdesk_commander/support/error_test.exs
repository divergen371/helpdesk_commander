defmodule HelpdeskCommander.Support.ErrorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias HelpdeskCommander.Support.Error

  test "log_error formats exception messages" do
    log =
      capture_log(fn ->
        Error.log_error("test.context", %RuntimeError{message: "boom"})
      end)

    assert log =~ "[test.context]"
    assert log =~ "boom"
  end

  test "log_warn formats non-exception values" do
    log =
      capture_log(fn ->
        Error.log_warn("test.warn", {:oops, 123})
      end)

    assert log =~ "[test.warn]"
    assert log =~ "{:oops, 123}"
  end
end
