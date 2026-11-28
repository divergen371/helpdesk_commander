defmodule HelpdeskCommander.DocsToolchainTest do
  @moduledoc """
  `.tool-versions` を唯一の真実として、live なドキュメントのツールチェーン表記が
  それとずれていないことを検証する。

  過去の事故（PR #17）: `.tool-versions` から asdf の `ref:` 表記を外したのに、
  `QUICKSTART.md` / `docs/STATUS.md` / `docs/ELIXIR_UPGRADE.md` が
  `asdf install` + `elixir ref:v1.20.4` のまま残り、レビューで差し戻された。
  読者が手順として辿るドキュメントは、コードと同じコミットで更新されている必要がある。
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  # 読者が手順・現状把握のために辿るドキュメント（live docs）
  @live_docs ~w(
    QUICKSTART.md
    docs/STATUS.md
    docs/ELIXIR_UPGRADE.md
  )

  # 除外（理由つき）:
  # - docs/Walkthrough.md は実装の記録（歴史的ログ）。当時の記述を書き換えない。
  # - doc/ は ExDoc の生成物。直接編集せず、生成し直して反映する。
  # - .specstory/ は会話ログ。

  setup_all do
    %{tool_versions: read_tool_versions()}
  end

  test ".tool-versions から elixir / erlang のバージョンを読める" do
    tool_versions = read_tool_versions()
    assert Map.has_key?(tool_versions, "elixir"), ".tool-versions に elixir が無い"
    assert Map.has_key?(tool_versions, "erlang"), ".tool-versions に erlang が無い"
  end

  test "live docs に asdf の git ref 表記 (ref:vX) が残っていない", _context do
    for doc <- doc_paths() do
      refute File.read!(doc) =~ ~r/\bref:v\d/,
             "#{rel(doc)} に asdf の `ref:vX` 表記が残っています。" <>
               " mise はこの表記を解決できないため `elixir <version>-otp-<n>` 形式にしてください"
    end
  end

  test "live docs は .tool-versions の Elixir バージョンを最低 1 箇所は載せている", %{
    tool_versions: tool_versions
  } do
    expected = Map.fetch!(tool_versions, "elixir")

    for doc <- doc_paths(),
        content = File.read!(doc),
        content =~ "Elixir" do
      assert content =~ expected,
             "#{rel(doc)} が Elixir に言及しているのに #{expected} が無い" <>
               "（.tool-versions を変えたら live docs も同じコミットで更新する）"
    end
  end

  test "live docs の `asdf install` は mise の代替としてのみ書かれている", _context do
    for doc <- doc_paths(),
        line <- String.split(File.read!(doc), "\n"),
        String.contains?(line, "asdf install") do
      assert String.contains?(line, "mise"),
             "#{rel(doc)} が `asdf install` を主手順として書いています（バージョン管理は mise）: #{inspect(line)}"
    end
  end

  defp doc_paths do
    @live_docs
    |> Enum.map(&Path.join(@root, &1))
    |> Enum.filter(&File.exists?/1)
  end

  defp read_tool_versions do
    @root
    |> Path.join(".tool-versions")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Map.new(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [tool, version] -> {tool, version}
        _ -> {line, ""}
      end
    end)
  end

  # `Elixir **1.20.4-otp-29**` / `Elixir 1.19.4` / `Elixir \`ref:v1.20.4\`` のような行を拾う
  defp rel(path), do: Path.relative_to(path, @root)
end
