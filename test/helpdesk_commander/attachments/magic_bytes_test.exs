defmodule HelpdeskCommander.Attachments.MagicBytesTest do
  use ExUnit.Case, async: true

  alias HelpdeskCommander.Attachments.MagicBytes

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, "IHDR">>
  @jpg <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>>
  @gif "GIF89a" <> <<1, 0, 1, 0, 0, 0>>
  @webp "RIFF" <> <<24, 0, 0, 0>> <> "WEBP" <> "VP8 "
  @pdf "%PDF-1.7\n"
  @zip "PK" <> <<0x03, 0x04>> <> "zip data"
  @exe "MZ" <> <<0x90, 0x00, 0x03, 0xFF>> <> "payload"
  @elf <<0x7F, "ELF", 0x02, 0x01, 0x01, 0x00>>

  setup do
    path = Path.join(System.tmp_dir!(), "magic-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(path) end)
    {:ok, path: path}
  end

  test "detects the allowed binary formats", %{path: path} do
    for {content, format} <- [
          {@png, :image_png},
          {@jpg, :image_jpg},
          {@gif, :image_gif},
          {@webp, :image_webp},
          {@pdf, :pdf},
          {@zip, :zip}
        ] do
      File.write!(path, content <> String.duplicate("x", 64))
      assert {:ok, ^format} = MagicBytes.sniff(path)
    end
  end

  test "classifies printable content as text", %{path: path} do
    File.write!(path, "hello world\nsecond line\n")
    assert {:ok, :text} = MagicBytes.sniff(path)
  end

  test "classifies utf-8 multibyte text as text", %{path: path} do
    File.write!(path, "日本語のテキストです。\n")
    assert {:ok, :text} = MagicBytes.sniff(path)
  end

  test "classifies an empty file as text", %{path: path} do
    File.write!(path, "")
    assert {:ok, :text} = MagicBytes.sniff(path)
  end

  test "classifies unrecognized binary content as unknown_binary", %{path: path} do
    for content <- [@exe, @elf, <<0x00, 0x01, 0x02>>] do
      File.write!(path, content)
      assert {:ok, :unknown_binary} = MagicBytes.sniff(path)
    end
  end

  test "returns a read error when the file does not exist" do
    assert {:error, {:read_error, _reason}} = MagicBytes.sniff("/tmp/does-not-exist-anything")
  end
end
