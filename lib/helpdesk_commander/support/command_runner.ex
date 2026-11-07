defmodule HelpdeskCommander.Support.CommandRunner do
  @moduledoc """
  外部コマンドをタイムアウト付きで実行する。

  `System.cmd/3` はコマンドが存在しない場合に例外を投げ、`Task.async` はリンクしている
  ため呼び出し元まで巻き込んで落ちる。このモジュールはタスク内で例外を捕捉し、
  タイムアウトも含めて `{:error, reason}` に正規化する。
  """

  @default_timeout 30_000

  @type result :: {:ok, String.t(), integer()} | {:error, term()}

  @spec run(String.t(), [String.t()], keyword()) :: result()
  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, sanitized_env())

    task =
      Task.async(fn ->
        try do
          {output, status} = System.cmd(command, args, stderr_to_stdout: true, env: env)
          {:ok, to_string(output), status}
        rescue
          error -> {:error, error}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:crash, reason}}
      nil -> {:error, :timeout}
    end
  end

  defp sanitized_env do
    [{"CLOAK_KEY", ""}, {"PII_HMAC_SECRET", ""}, {"SECRET_KEY_BASE", ""}, {"DATABASE_URL", ""}]
  end
end
