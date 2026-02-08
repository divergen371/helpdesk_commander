defmodule Mix.Tasks.Precommit do
  @shortdoc "Run precommit checks (compile, deps unlock, format, credo, test)"

  @moduledoc """
  Runs the standard precommit checks in a consistent order.

  Supports `--all` which is forwarded to `mix credo` and ignored for `mix test`.
  Any other arguments are passed through to `mix test`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {all?, test_args} = split_all_flag(args)
    credo_args = build_credo_args(all?)

    Mix.Task.run("compile", ["--warnings-as-errors"])
    Mix.Task.run("deps.unlock", ["--unused"])
    Mix.Task.run("format", [])
    Mix.Task.run("credo", credo_args)
    Mix.Task.run("test", test_args)
  end

  defp split_all_flag(args) do
    {all?, reversed_args} =
      Enum.reduce(args, {false, []}, fn arg, {all?, acc} ->
        if arg == "--all" do
          {true, acc}
        else
          {all?, [arg | acc]}
        end
      end)

    {all?, Enum.reverse(reversed_args)}
  end

  defp build_credo_args(all?) do
    if all? do
      ["--strict", "--all"]
    else
      ["--strict"]
    end
  end
end
