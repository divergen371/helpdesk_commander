defmodule HelpdeskCommander.Reports.Pdf do
  @moduledoc """
  依存なしで単純な PDF（Helvetica・テキストのみ）を生成する（HC-29）。

  運用レポートの添付用であり、図表・フォント埋め込みは扱わない。
  出力はページ数・オフセットを正確に計算した有効な PDF 1.4 である。
  """

  @page_width 595
  @page_height 842
  @margin 48
  @line_height 16
  @heading_height 30
  @title_height 34
  @max_chars_per_line 90

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
    case String.length(line) <= @max_chars_per_line do
      true ->
        [line]

      false ->
        {chunk, rest} = String.split_at(line, @max_chars_per_line)
        [chunk | wrap_line(rest)]
    end
  end

  defp wrap_line(other), do: [inspect(other)]

  defp escape(text) do
    text
    |> to_string()
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
    offsets = compute_offsets(chunks)
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

  defp compute_offsets(chunks) do
    chunks
    |> Enum.map_reduce(0, fn chunk, cursor ->
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
