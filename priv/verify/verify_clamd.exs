#!/usr/bin/env elixir
# clamd サイドカーの疎通確認（HC-21 / AC#4）
#
#   ATTACHMENT_SCAN_CLAMD_HOST=127.0.0.1 ATTACHMENT_SCAN_CLAMD_PORT=3310 \
#     mix run priv/verify/verify_clamd.exs
#
# PING → VERSION → 良性ファイル（clean）→ EICAR 検体（infected）の順に確認する。
# 1 つでも失敗したら exit 1。アプリの DB は使わない。

alias HelpdeskCommander.Attachments.Clamd

host = System.get_env("ATTACHMENT_SCAN_CLAMD_HOST", "127.0.0.1")
port = String.to_integer(System.get_env("ATTACHMENT_SCAN_CLAMD_PORT", "3310"))
config = %{host: host, port: port, timeout_ms: 30_000}

eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

tmp = System.tmp_dir!()
benign_path = Path.join(tmp, "verify_clamd_benign_#{System.unique_integer([:positive])}.txt")
eicar_path = Path.join(tmp, "verify_clamd_eicar_#{System.unique_integer([:positive])}.txt")

File.write!(benign_path, "benign content\n")
File.write!(eicar_path, eicar)

steps = [
  {"PING", fn ->
    case Clamd.ping(config) do
      {:ok, "PONG"} -> :ok
      other -> {:fail, {:ping, other}}
    end
  end},
  {"VERSION", fn ->
    case Clamd.version(config) do
      {:ok, version} ->
        IO.puts("  version: #{version}")
        :ok

      other ->
        {:fail, {:version, other}}
    end
  end},
  {"clean（良性ファイル）", fn ->
    case Clamd.scan_file(benign_path, config) do
      {:ok, :clean, note} ->
        IO.puts("  clean: #{note}")
        :ok

      other ->
        {:fail, {:clean, other}}
    end
  end},
  {"infected（EICAR 検体）", fn ->
    case Clamd.scan_file(eicar_path, config) do
      {:ok, :infected, detection} ->
        IO.puts("  infected: #{detection}")
        :ok

      other ->
        {:fail, {:infected, other}}
    end
  end}
]

results =
  Enum.map(steps, fn {label, fun} ->
    case fun.() do
      :ok ->
        IO.puts("ok   #{label}")
        true

      {:fail, reason} ->
        IO.puts("FAIL #{label}: #{inspect(reason)}")
        false

      other ->
        IO.puts("FAIL #{label}: #{inspect(other)}")
        false
    end
  end)

File.rm(benign_path)
File.rm(eicar_path)

if Enum.all?(results) do
  IO.puts("clamd sandbox check passed")
  System.stop(0)
else
  IO.puts("clamd sandbox check FAILED")
  System.stop(1)
end
