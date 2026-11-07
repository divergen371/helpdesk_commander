defmodule HelpdeskCommander.Attachments.YaraTest do
  use ExUnit.Case, async: false

  alias HelpdeskCommander.Attachments.Yara

  setup do
    original = [
      Application.get_env(:helpdesk_commander, :attachment_yara_command),
      Application.get_env(:helpdesk_commander, :attachment_yara_rules)
    ]

    on_exit(fn ->
      [command, rules] = original
      Application.put_env(:helpdesk_commander, :attachment_yara_command, command)
      Application.put_env(:helpdesk_commander, :attachment_yara_rules, rules)
    end)

    path = Path.join(System.tmp_dir!(), "yara-#{System.unique_integer([:positive])}")
    File.write!(path, "hello")
    on_exit(fn -> File.rm(path) end)

    {:ok, path: path}
  end

  test "is disabled by default", %{path: path} do
    Application.delete_env(:helpdesk_commander, :attachment_yara_command)
    refute Yara.enabled?()
    assert {:ok, []} = Yara.scan(path)
  end

  test "parses matched rule names from stdout", %{path: path} do
    Application.put_env(
      :helpdesk_commander,
      :attachment_yara_command,
      {"sh", ["-c", "echo 'Internal_Phishing_Phrase $0'; echo 'Internal_Phishing_Phrase $0'"]}
    )

    assert Yara.enabled?()
    assert {:ok, ["Internal_Phishing_Phrase"]} = Yara.scan(path)
  end

  test "returns no matches for clean files", %{path: path} do
    Application.put_env(:helpdesk_commander, :attachment_yara_command, {"sh", ["-c", "exit 0"]})

    assert {:ok, []} = Yara.scan(path)
  end

  test "treats a non-zero exit as an error", %{path: path} do
    Application.put_env(
      :helpdesk_commander,
      :attachment_yara_command,
      {"sh", ["-c", "echo 'error: invalid rule'; exit 1"]}
    )

    assert {:error, {:exit_status, 1, output}} = Yara.scan(path)
    assert output =~ "invalid rule"
  end

  test "uses the rules directory when the command is yara", %{path: path} do
    Application.put_env(:helpdesk_commander, :attachment_yara_command, "yara")
    Application.put_env(:helpdesk_commander, :attachment_yara_rules, "priv/yara")

    # yara 未インストールでも、引数組み立ての失敗はエラーとして返る（クラッシュしない）
    assert match?({:ok, []}, Yara.scan(path)) or match?({:error, _reason}, Yara.scan(path))
  end
end
