IEx.configure(history_size: 200)

IEx.configure(
  inspect: [
    pretty: true,
    limit: :infinity,
    printable_limit: :infinity,
    width: 120
  ]
)

defmodule IExHelpers do
  @moduledoc false

  def env, do: Mix.env()

  def cls do
    IO.write("\e[H\e[2J")
    :ok
  end

  def pp_error(fun) when is_function(fun, 0) do
    fun.()
  rescue
    e ->
      IO.puts(Exception.format(:error, e, __STACKTRACE__))
      {:error, e}
  end
end

import IExHelpers

# --- Ecto ---------------------------------------------------------------
if Code.ensure_loaded?(Ecto.Query) do
  import Ecto.Query
end

# Repo（変数で alias できないので分岐で直書き）
cond do
  Code.ensure_loaded?(HelpdeskCommander.Repo) ->
    alias HelpdeskCommander.Repo, as: Repo

  true ->
    :ok
end

# --- Phoenix ------------------------------------------------------------
cond do
  Code.ensure_loaded?(HelpdeskCommanderWeb.Router.Helpers) ->
    alias HelpdeskCommanderWeb.Router.Helpers, as: Routes

  Code.ensure_loaded?(HelpdeskCommanderWeb.Routes) ->
    alias HelpdeskCommanderWeb.Routes, as: Routes

  true ->
    :ok
end

if Code.ensure_loaded?(HelpdeskCommanderWeb.Endpoint) do
  alias HelpdeskCommanderWeb.Endpoint
end

# --- Ash ---------------------------------------------------------------
if Code.ensure_loaded?(Ash.Query) do
  import Ash.Query
end
