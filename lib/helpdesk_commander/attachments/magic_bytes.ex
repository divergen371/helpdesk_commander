defmodule HelpdeskCommander.Attachments.MagicBytes do
  @moduledoc """
  ファイル先頭バイトから形式を推定する（HC-19）。

  拡張子と MIME はクライアントの申告なので、実体と照合して偽装を防ぐ。判定は 3 択:

  - `:image_png` / `:image_jpg` / `:image_gif` / `:image_webp` / `:pdf` / `:zip`
    — マジックバイトが署名と一致した形式。対応する拡張子でのみ許可する
  - `:text` — 署名なしで先頭 512 バイトが表示可能テキスト（NUL・制御文字を含まない）。
    テキスト用拡張子（txt / csv）でのみ許可する
  - `:unknown_binary` — どの署名にも一致せずテキストでもない実行バイナリ等。
    すべての拡張子で拒否する
  """

  @head_bytes 512

  @type format ::
          :image_png | :image_jpg | :image_gif | :image_webp | :pdf | :zip | :text | :unknown_binary

  @doc "先頭 512 バイトを読んで形式を推定する。読めないときは read_error。"
  @spec sniff(String.t()) :: {:ok, format()} | {:error, {:read_error, term()}}
  def sniff(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, @head_bytes)) do
      {:ok, data} -> {:ok, classify(data)}
      {:error, reason} -> {:error, {:read_error, reason}}
    end
  end

  defp classify(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>) do
    :image_png
  end

  defp classify(<<0xFF, 0xD8, 0xFF, _rest::binary>>) do
    :image_jpg
  end

  defp classify(<<"GIF8", _rest::binary>>) do
    :image_gif
  end

  defp classify(<<_raster_size::binary-size(8), "WEBP", _rest::binary>>) do
    :image_webp
  end

  defp classify(<<"%PDF", _rest::binary>>) do
    :pdf
  end

  defp classify(<<"PK", 0x03, 0x04, _rest::binary>>) do
    :zip
  end

  # IO.binread は空のファイルで :eof を返す
  defp classify(:eof) do
    :text
  end

  defp classify(data) when is_binary(data) do
    if text?(data), do: :text, else: :unknown_binary
  end

  # NUL と典型的なバイナリ制御文字が 1 バイトでもあればテキストとみなさない。
  # \t \n \r と 0x20..0x7E は許可する。UTF-8 のマルチバイト（0x80 以上）も許可する。
  defp text?(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.any?(&non_text_byte?/1)
    |> Kernel.not()
  end

  defp non_text_byte?(0x00), do: true
  defp non_text_byte?(byte) when byte < 0x09, do: true
  defp non_text_byte?(0x0A), do: false
  defp non_text_byte?(0x0D), do: false
  defp non_text_byte?(0x09), do: false
  defp non_text_byte?(byte) when byte < 0x20, do: true
  defp non_text_byte?(0x7F), do: true
  defp non_text_byte?(_byte), do: false
end
