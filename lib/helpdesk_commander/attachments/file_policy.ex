defmodule HelpdeskCommander.Attachments.FilePolicy do
  @moduledoc """
  添付ファイルの拡張子・MIME・容量・実体（マジックバイト）を検証する。

  拡張子ごとに許可する MIME を固定し、ブラウザが付ける代表的な別名だけを許容する。
  さらにファイル先頭のマジックバイトを拡張子と照合して偽装を防ぐ（HC-19）。
  容量は 1 ファイル 10MB、1 回 3 件まで（LiveView 側の制限と合わせる）。
  """

  alias HelpdeskCommander.Attachments.MagicBytes

  @max_file_size 10 * 1024 * 1024
  @max_entries 3

  @allowed %{
    ".png" => ~w(image/png),
    ".jpg" => ~w(image/jpeg),
    ".jpeg" => ~w(image/jpeg),
    ".gif" => ~w(image/gif),
    ".webp" => ~w(image/webp),
    ".pdf" => ~w(application/pdf),
    ".txt" => ~w(text/plain),
    ".csv" => ~w(text/csv text/plain application/vnd.ms-excel application/octet-stream),
    ".zip" => ~w(application/zip application/x-zip-compressed application/octet-stream),
    ".docx" => ~w(application/vnd.openxmlformats-officedocument.wordprocessingml.document),
    ".xlsx" => ~w(application/vnd.openxmlformats-officedocument.spreadsheetml.sheet),
    ".pptx" => ~w(application/vnd.openxmlformats-officedocument.presentationml.presentation)
  }

  # マジックバイトで判別できる形式と、それを許可する拡張子の対応。
  # テキスト（:text）はテキスト用拡張子でのみ許し、認識不能なバイナリ
  # （:unknown_binary）はすべての拡張子で拒否する。
  @format_extensions %{
    image_png: [".png"],
    image_jpg: [".jpg", ".jpeg"],
    image_gif: [".gif"],
    image_webp: [".webp"],
    pdf: [".pdf"],
    zip: [".zip", ".docx", ".xlsx", ".pptx"]
  }

  @text_extensions [".txt", ".csv"]

  @spec extensions() :: [String.t()]
  def extensions, do: Map.keys(@allowed)

  @spec accept() :: [String.t()]
  def accept, do: extensions()

  @spec max_file_size() :: 10_485_760
  def max_file_size, do: @max_file_size

  @spec max_entries() :: 3
  def max_entries, do: @max_entries

  @spec validate(Plug.Upload.t()) :: :ok | {:error, atom()}
  def validate(%Plug.Upload{} = upload) do
    extension = upload.filename |> Path.extname() |> String.downcase()
    content_type = upload.content_type |> to_string() |> String.split(";") |> hd() |> String.trim() |> String.downcase()

    cond do
      not Map.has_key?(@allowed, extension) -> {:error, :extension_not_allowed}
      content_type not in Map.fetch!(@allowed, extension) -> {:error, :content_type_not_allowed}
      not File.exists?(upload.path) -> {:error, :missing_file}
      File.stat!(upload.path).size > @max_file_size -> {:error, :too_large}
      not magic_matches?(upload.path, extension) -> {:error, :content_magic_mismatch}
      true -> :ok
    end
  end

  def validate(_upload), do: {:error, :invalid_upload}

  defp magic_matches?(path, extension) do
    case MagicBytes.sniff(path) do
      {:ok, :text} -> extension in @text_extensions
      {:ok, :unknown_binary} -> false
      {:ok, format} -> extension in Map.fetch!(@format_extensions, format)
      {:error, _reason} -> false
    end
  end
end
