defmodule HelpdeskCommander.Reports.Pdf do
  @moduledoc """
  依存なしで単純な PDF（Helvetica・ASCII テキストのみ）を生成する（HC-29）。

  運用レポートの添付用であり、図表・フォント埋め込みは扱わない。
  base-14 Helvetica で表現できる ASCII のみを出力し、非 ASCII は `?` に置換する。
  日本語ラベルは呼び出し側で ASCII に置き換えること。
  出力はページ数・オフセットを正確に計算した有効な PDF 1.4 である。
  """

  @page_width 595
  @page_height 842
  @margin 48
  @line_height 16
  @heading_height 30
  @title_height 34
  @max_display_width 180

  @doc """
  タイトルと節（`{見出し, [行]}`）から PDF バイト列を返す。
  """
  @spec generate(String.t(), [{String.t(), [String.t()]}]) :: binary()
  def generate(title, sections) when is_binary(title) and is_list(sections) do
    sections
    |> layout(title)
    |> flush_final()
    |> build_objects_from_streams()
    |> emit()
  end

  defp build_objects_from_streams([]), do: build_objects(["(empty report)\n"])
  defp build_objects_from_streams(streams), do: build_objects(streams)

  # レイアウト ---------------------------------------------------------------

  defp layout(sections, title) do
    empty_state = %{pages: [], lines: [], y: @page_height - @margin}

    initial = put_title(empty_state, title)
    layout_fn = fn {heading, lines}, acc -> acc |> put_heading(heading) |> put_lines(lines) end
    Enum.reduce(sections, initial, layout_fn)
  end

  defp put_title(state, title) do
    y = state.y - @title_height

    add_fragment(state, text_fragment(title, 20, y), y)
  end

  defp put_heading(state, heading) do
    case state.y - @heading_height < @margin do
      true -> put_heading(flush_current(state), heading)
      false -> write_line(state, heading, 15, @heading_height)
    end
  end

  defp put_lines(state, contents) do
    contents
    |> Enum.flat_map(&wrap_line/1)
    |> Enum.reduce(state, &put_line(&1, &2))
  end

  defp put_line(line, state) do
    case state.y - @line_height < @margin do
      true -> put_line(line, flush_current(state))
      false -> write_line(state, line, 11, @line_height)
    end
  end

  defp write_line(state, text, size, step) do
    y = state.y - step
    add_fragment(state, text_fragment(text, size, y), y)
  end

  defp add_fragment(state, fragment, y) do
    %{state | lines: [fragment | state.lines], y: y}
  end

  defp flush_current(state) do
    page = state.lines |> Enum.reverse() |> IO.iodata_to_binary()

    state
    |> Map.put(:pages, [page | state.pages])
    |> Map.merge(%{lines: [], y: @page_height - @margin})
  end

  defp flush_final(state) do
    case state.lines do
      [] -> Enum.reverse(state.pages)
      _lines -> state |> flush_current() |> Map.get(:pages, []) |> Enum.reverse()
    end
  end

  defp text_fragment(text, size, y) do
    ["BT /F1 #{size} Tf 1 0 0 1 #{@margin} #{y} Tm (", escape(text), ") Tj ET\n"]
  end

  defp wrap_line(line) when is_binary(line) do
    case display_width(line) <= @max_display_width do
      true ->
        [line]

      false ->
        {chunk, rest} = split_by_width(line, @max_display_width)
        [chunk | wrap_line(rest)]
    end
  end

  defp wrap_line(other), do: [inspect(other)]

  defp display_width(text) do
    text
    |> to_string()
    |> String.codepoints()
    |> Enum.reduce(0, fn cp, width -> width + char_width(cp) end)
  end

  # 基本ラテン文字は半角幅、その他（全角・CJK 等）は 2 倍として概算する。
  defp char_width(cp) do
    case byte_size(cp) do
      1 -> 1
      _size -> 2
    end
  end

  defp split_by_width(text, limit) do
    text = to_string(text)
    graphemes = String.graphemes(text)

    taken_rev =
      graphemes
      |> Enum.reduce_while({[], 0}, fn grapheme, {acc, width} ->
        w = char_width(grapheme)

        case acc != [] and width + w > limit do
          true -> {:halt, {acc, true}}
          false -> {:cont, {[grapheme | acc], width + w}}
        end
      end)
      |> elem(0)

    taken = taken_rev |> Enum.reverse() |> length()

    {String.slice(text, 0, taken), String.slice(text, taken..-1//1)}
  end

  @doc """
  PDF 本文は base-14 Helvetica（WinAnsi 相当）で表現できる ASCII を前提とする。

  非 ASCII の文字は `?` に置換する。日本語ラベルは呼び出し側（`Reports.Scheduled`）で
  ASCII に置き換えてから渡すこと。
  """
  @spec ascii_safe(String.t()) :: String.t()
  def ascii_safe(text) do
    text
    |> to_string()
    |> String.codepoints()
    |> Enum.map_join(&ascii_char/1)
  end

  defp ascii_char(cp) do
    case byte_size(cp) do
      1 -> cp
      _size -> "?"
    end
  end

  defp escape(text) do
    text
    |> ascii_safe()
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end

  # オブジェクト構築 ----------------------------------------------------------

  defp build_objects(page_streams) do
    page_count = length(page_streams)
    first_page_obj = 4

    {page_objects, page_refs_rev} =
      page_streams
      |> Enum.with_index(first_page_obj)
      |> Enum.map_reduce([], fn {stream, index}, refs ->
        page_dict = page_dict(index)
        content_dict = content_dict(stream)

        {[
           {page_dict, nil},
           {content_dict, nil}
         ], ["#{index} 0 R" | refs]}
      end)

    page_refs = page_refs_rev |> Enum.reverse() |> Enum.join(" ")

    [
      {"<< /Type /Catalog /Pages 2 0 R >>", nil},
      {"<< /Type /Pages /Count #{page_count} /Kids [#{page_refs}] >>", nil},
      {"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", nil}
      | List.flatten(page_objects)
    ]
  end

  defp page_dict(index) do
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{@page_width} #{@page_height}] " <>
      "/Resources << /Font << /F1 3 0 R >> >> /Contents #{index + 1} 0 R >>"
  end

  defp content_dict(stream) do
    "<< /Length #{IO.iodata_length(stream)} >>\nstream\n#{stream}endstream"
  end

  defp emit(objects) do
    header = "%PDF-1.4\n"
    chunks = render_chunks(objects)
    offsets = compute_offsets(chunks, byte_size(header))
    startxref = byte_size(header) + IO.iodata_length(chunks)

    IO.iodata_to_binary([
      header,
      chunks,
      xref_table(offsets, length(objects)),
      "trailer\n",
      "<< /Size #{length(objects) + 1} /Root 1 0 R >>\n",
      "startxref\n",
      Integer.to_string(startxref),
      "\n%%EOF"
    ])
  end

  defp render_chunks(objects) do
    objects
    |> Enum.with_index(1)
    |> Enum.map(fn {{dict, nil}, number} ->
      IO.iodata_to_binary(["#{number} 0 obj\n", dict, "\nendobj\n"])
    end)
  end

  defp compute_offsets(chunks, start) do
    chunks
    |> Enum.map_reduce(start, fn chunk, cursor ->
      size = IO.iodata_length(chunk)
      {cursor, cursor + size}
    end)
    |> elem(0)
  end

  defp xref_table(offsets, count) do
    [
      "xref\n",
      "0 #{count + 1}\n",
      "0000000000 65535 f \n",
      Enum.map(offsets, &:io_lib.format("~10..0B 00000 n \n", [&1]))
    ]
  end
end
