defmodule HelpdeskCommander.Reports.PdfTest do
  use ExUnit.Case, async: true

  @sections [
    {"サマリ", ["期間: 2026-11-01 〜 2026-11-30", "チケット総数: 42"]},
    {"ステータス別", ["new: 3", "in_progress: 7"]}
  ]

  test "generates a valid PDF with header, xref, and EOF marker" do
    pdf = HelpdeskCommander.Reports.Pdf.generate("運用レポート", @sections)

    assert String.starts_with?(pdf, "%PDF-1.4\n")
    assert pdf =~ "%%EOF"
    assert pdf =~ "xref\n"
    assert pdf =~ "(運用レポート) Tj"
    assert pdf =~ "(チケット総数: 42) Tj"

    startxref =
      pdf
      |> String.split("startxref\n")
      |> List.last()
      |> String.split("\n")
      |> hd()
      |> String.to_integer()

    assert binary_part(pdf, startxref, 4) == "xref"
  end

  test "escapes parentheses and backslashes in text" do
    pdf = HelpdeskCommander.Reports.Pdf.generate("t", [{"見出し", ["含む(括弧)と\\記号"]}])

    assert pdf =~ "含む\\(括弧\\)と\\\\記号"
  end

  test "wraps long lines and paginates many sections" do
    long_line = String.duplicate("あ", 120)
    many = Enum.map(1..40, &{"見出し #{&1}", [long_line]})

    pdf = HelpdeskCommander.Reports.Pdf.generate("長文", many)

    assert pdf =~ "/Count "
    # 複数ページが生成されている
    assert pdf |> String.split("/Type /Page ") |> length() > 2
  end
end
