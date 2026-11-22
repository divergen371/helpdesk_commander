defmodule HelpdeskCommander.Reports.PdfTest do
  use ExUnit.Case, async: true

  @sections [
    {"Summary", ["Period: 2026-11-01 - 2026-11-30", "Total tickets: 42"]},
    {"By status", ["new: 3", "in_progress: 7"]}
  ]

  test "generates a valid PDF with header, xref, and EOF marker" do
    pdf = HelpdeskCommander.Reports.Pdf.generate("Operations report", @sections)

    assert String.starts_with?(pdf, "%PDF-1.4\n")
    assert pdf =~ "%%EOF"
    assert pdf =~ "xref\n"
    assert pdf =~ "(Operations report) Tj"
    assert pdf =~ "(Total tickets: 42) Tj"

    startxref =
      pdf
      |> String.split("startxref\n")
      |> List.last()
      |> String.split("\n")
      |> hd()
      |> String.to_integer()

    assert binary_part(pdf, startxref, 4) == "xref"
  end

  test "xref offsets are absolute from the start of the file" do
    pdf = HelpdeskCommander.Reports.Pdf.generate("t", @sections)
    header_size = byte_size("%PDF-1.4\n")

    offsets =
      pdf
      |> String.split("xref\n0 ")
      |> List.last()
      |> String.split("\n")
      |> Enum.drop(2)
      |> Enum.filter(&String.starts_with?(&1, "0000"))
      |> Enum.map(&String.slice(&1, 0, 10))
      |> Enum.map(&String.to_integer/1)

    # 最初のオブジェクト（Catalog）はヘッダ直後に配置される
    assert hd(offsets) == header_size
    assert binary_part(pdf, hd(offsets), 8) == "1 0 obj\n"

    # 以降のエントリも実オブジェクト位置を指す
    Enum.each(tl(offsets), fn offset ->
      assert binary_part(pdf, offset, 8) =~ " obj\n"
    end)
  end

  test "escapes parentheses and backslashes in text" do
    pdf = HelpdeskCommander.Reports.Pdf.generate("t", [{"heading", ["contains (parens) and \\ sym"]}])

    assert pdf =~ "contains \\(parens\\) and \\\\ sym"
  end

  test "replaces non-ASCII characters with ? (base-14 Helvetica is ASCII only)" do
    pdf = HelpdeskCommander.Reports.Pdf.generate("t", [{"heading", ["日本語とmixed"]}])

    refute pdf =~ "日本語"
    assert pdf =~ "??mixed"
  end

  test "wraps long lines by display width and paginates many sections" do
    long_line = String.duplicate("a", 250)
    many = Enum.map(1..40, &{"heading #{&1}", [long_line]})

    pdf = HelpdeskCommander.Reports.Pdf.generate("long", many)

    # 複数ページが生成されている
    assert pdf |> String.split("/Type /Page ") |> length() > 2
    assert pdf =~ "heading 40"
  end
end
