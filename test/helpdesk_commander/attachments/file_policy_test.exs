defmodule HelpdeskCommander.Attachments.FilePolicyTest do
  use ExUnit.Case, async: true

  alias HelpdeskCommander.Attachments.FilePolicy

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, "IHDR">>
  @jpg <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>>
  @gif "GIF89a" <> <<1, 0, 1, 0, 0, 0>>
  @webp "RIFF" <> <<24, 0, 0, 0>> <> "WEBP" <> "VP8 "
  @pdf "%PDF-1.7\n"
  @zip "PK" <> <<0x03, 0x04>> <> "zip data"
  @exe "MZ" <> <<0x90, 0x00, 0x03, 0xFF>> <> "payload"

  setup do
    path = Path.join(System.tmp_dir!(), "policy-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(path) end)
    {:ok, path: path}
  end

  defp upload(path, filename, content, content_type) do
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  test "accepts files whose extension, MIME and magic bytes agree", %{path: path} do
    uploads = [
      {"image.png", @png, "image/png"},
      {"photo.jpg", @jpg, "image/jpeg"},
      {"photo.jpeg", @jpg, "image/jpeg"},
      {"icon.gif", @gif, "image/gif"},
      {"render.webp", @webp, "image/webp"},
      {"doc.pdf", @pdf, "application/pdf"},
      {"archive.zip", @zip, "application/zip"},
      {"report.docx", @zip, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
      {"sheet.xlsx", @zip, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
      {"slides.pptx", @zip, "application/vnd.openxmlformats-officedocument.presentationml.presentation"},
      {"note.txt", "plain text", "text/plain"},
      {"data.csv", "a,b,c", "text/csv"}
    ]

    for {filename, content, content_type} <- uploads do
      assert :ok = FilePolicy.validate(upload(path, filename, content, content_type)), "expected #{filename} to pass"
    end
  end

  test "rejects content whose magic bytes do not match the extension", %{path: path} do
    for {filename, content, content_type} <- [
          {"fake.png", @zip, "image/png"},
          {"fake.pdf", @png, "application/pdf"},
          {"fake.gif", @jpg, "image/gif"},
          {"fake.webp", @png, "image/webp"},
          {"fake.jpg", @exe, "image/jpeg"},
          {"fake.docx", @png, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"}
        ] do
      assert {:error, :content_magic_mismatch} =
               FilePolicy.validate(upload(path, filename, content, content_type))
    end
  end

  test "rejects text content with a binary extension", %{path: path} do
    assert {:error, :content_magic_mismatch} =
             FilePolicy.validate(upload(path, "image.png", "plain text", "image/png"))

    assert {:error, :content_magic_mismatch} =
             FilePolicy.validate(upload(path, "doc.pdf", "plain text", "application/pdf"))
  end

  test "rejects binary content disguised as a text file", %{path: path} do
    for content <- [@exe, @png, @zip] do
      assert {:error, :content_magic_mismatch} =
               FilePolicy.validate(upload(path, "run.txt", content, "text/plain"))
    end
  end

  test "accepts uppercase extensions and MIME parameters" do
    path = Path.join(System.tmp_dir!(), "policy-case-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(path) end)

    assert :ok = FilePolicy.validate(upload(path, "PHOTO.PNG", @png, "IMAGE/PNG"))
    assert :ok = FilePolicy.validate(upload(path, "note.txt", "text", " TEXT/PLAIN ; charset=utf-8"))
  end

  test "enforces the exact size boundary", %{path: path} do
    File.write!(path, :binary.copy("a", FilePolicy.max_file_size()))

    assert :ok =
             FilePolicy.validate(%Plug.Upload{
               path: path,
               filename: "note.txt",
               content_type: "text/plain"
             })

    File.write!(path, :binary.copy("a", FilePolicy.max_file_size() + 1))

    assert {:error, :too_large} =
             FilePolicy.validate(%Plug.Upload{
               path: path,
               filename: "note.txt",
               content_type: "text/plain"
             })
  end

  test "reports a missing file as missing_file" do
    missing = Path.join(System.tmp_dir!(), "missing-#{System.unique_integer([:positive])}")

    assert {:error, :missing_file} =
             FilePolicy.validate(%Plug.Upload{
               path: missing,
               filename: "note.txt",
               content_type: "text/plain"
             })
  end

  test "rejects values that are not uploads" do
    assert {:error, :invalid_upload} = FilePolicy.validate(:not_upload)
    assert {:error, :invalid_upload} = FilePolicy.validate(%{})
  end

  test "rejects uploads that cannot be read", %{path: path} do
    File.mkdir_p!(path)

    assert {:error, :content_magic_mismatch} =
             FilePolicy.validate(%Plug.Upload{path: path, filename: "note.txt", content_type: "text/plain"})
  end
end
