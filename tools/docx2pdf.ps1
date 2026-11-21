# docx2pdf.ps1 —— 用本机 Word 把 DOCX 转成 PDF，并先更新目录域与页码
#
# 用法：
#   powershell -File tools/docx2pdf.ps1 -Docx "docs/01-系统设计说明书.docx" -Pdf "docs/01-系统设计说明书.pdf"
#
# 说明：
#   python-docx 只能写入 TOC 域，无法计算页码，必须由 Word 更新一次域，
#   否则 PDF 里的目录是一行提示文字。本脚本负责这一步。

param(
    [Parameter(Mandatory = $true)][string]$Docx,
    [Parameter(Mandatory = $true)][string]$Pdf
)

$ErrorActionPreference = "Stop"

$docxPath = (Resolve-Path $Docx).Path
if ([System.IO.Path]::IsPathRooted($Pdf)) {
    $pdfPath = $Pdf
} else {
    $pdfPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Pdf))
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$word.Options.UpdateFieldsAtPrint = $true

try {
    $doc = $word.Documents.Open($docxPath, $false, $false)

    # 更新目录（存在才更新）
    if ($doc.TablesOfContents.Count -gt 0) {
        for ($i = 1; $i -le $doc.TablesOfContents.Count; $i++) {
            $doc.TablesOfContents.Item($i).Update()
        }

        # 更新域会重置目录样式，因此必须在 Update 之后设置
        foreach ($n in @("TOC 1", "TOC 2", "TOC 3")) {
            try {
                $st = $doc.Styles.Item($n)
                $st.Font.Size = 10.5
                $st.Font.Bold = $false
                $st.ParagraphFormat.SpaceBefore = 0
                $st.ParagraphFormat.SpaceAfter = 0
                $st.ParagraphFormat.LineSpacingRule = 4   # wdLineSpaceExactly
                $st.ParagraphFormat.LineSpacing = 12.5
            }
            catch { }
        }
        $doc.TablesOfContents.Item(1).Update()
    }
    $doc.Fields.Update() | Out-Null
    $doc.Repaginate()

    $pages = $doc.ComputeStatistics(2)
    $words = $doc.ComputeStatistics(0)

    # wdExportFormatPDF=17，CreateBookmarks=1（按标题生成 PDF 书签）
    # 参数按位置传：OpenAfterExport, OptimizeFor, Range, From, To, Item,
    #              IncludeDocProps, KeepIRM, CreateBookmarks
    $doc.ExportAsFixedFormat($pdfPath, 17, $false, 0, 0, 0, 0, 0, $true, $false, 1)
    $doc.Save()
    $doc.Close(0)

    Write-Output "PDF=$pdfPath"
    Write-Output "pages=$pages words=$words"
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
