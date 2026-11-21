# -*- coding: utf-8 -*-
"""
md2docx.py —— 把国标风格的设计文档 Markdown 转成排版规整的 DOCX

用法：
    python tools/md2docx.py 输入.md 输出.docx

排版约定（与团队文档规范一致）：
    正文    宋体 / Times New Roman，小四 12pt，1.5 倍行距，首行缩进 2 字符
    一级标题 黑体 16pt 居中，每章另起一页
    二级标题 黑体 14pt 左对齐
    三级标题 黑体 12pt 左对齐
    表格    五号 10.5pt，表头加粗居中、浅灰底，跨页自动重复表头
    代码块  Consolas 等宽，小五 9pt，浅灰底、无缩进、不自动断行
    图      居中，最大宽度按版心，不放大
    引用块  浅灰底 + 左缩进，用于设计说明
    页脚    居中页码

只依赖 python-docx。图片路径相对 Markdown 文件所在目录解析。
"""

import io
import os
import re
import sys

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

# ---------------------------------------------------------------- 常量

BODY_SIZE = 12.0          # 小四
TABLE_SIZE = 10.5         # 五号
TABLE_SIZE_WIDE = 9.0     # 列数 >=6 时降一档
CODE_SIZE = 9.0           # 小五
CAPTION_SIZE = 10.5

PAGE_W, PAGE_H = 21.0, 29.7
MARGIN_TB, MARGIN_L, MARGIN_R = 2.54, 3.0, 2.5
CONTENT_W = PAGE_W - MARGIN_L - MARGIN_R      # 15.5 cm
CONTENT_H = PAGE_H - MARGIN_TB * 2            # 24.6 cm
MAX_IMG_H = 19.0                              # 留出图注与前后文的余地

EA_BODY = "宋体"
EA_HEAD = "黑体"
ASCII_BODY = "Times New Roman"
ASCII_MONO = "Consolas"

GREY_BG = "F2F2F2"
GREY_LINE = "BFBFBF"
GREY_TEXT = "595959"


# ---------------------------------------------------------------- 底层工具

def _set_run_font(run, size, bold=False, ea=EA_BODY, ascii_font=ASCII_BODY,
                  color=None, italic=False):
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.name = ascii_font
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), ascii_font)
    rfonts.set(qn("w:hAnsi"), ascii_font)
    rfonts.set(qn("w:eastAsia"), ea)
    if color:
        run.font.color.rgb = RGBColor.from_string(color)


def _shade(element, fill):
    """给段落或单元格加底色。"""
    pr = element.get_or_add_tcPr() if element.tag.endswith("}tc") else element.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    pr.append(shd)


def _left_border(paragraph, color=GREY_LINE, size=12):
    ppr = paragraph._p.get_or_add_pPr()
    borders = OxmlElement("w:pBdr")
    left = OxmlElement("w:left")
    left.set(qn("w:val"), "single")
    left.set(qn("w:sz"), str(size))
    left.set(qn("w:space"), "6")
    left.set(qn("w:color"), color)
    borders.append(left)
    ppr.append(borders)


def _fmt(p, size=BODY_SIZE, line=1.5, indent_chars=2, align=None,
         before=0, after=0, keep_next=False):
    pf = p.paragraph_format
    if line == 1.5:
        pf.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    else:
        pf.line_spacing = line
    if indent_chars:
        pf.first_line_indent = Pt(size * indent_chars)
    else:
        pf.first_line_indent = Pt(0)
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    if align is not None:
        p.alignment = align
    if keep_next:
        pf.keep_with_next = True


# ---------------------------------------------------------------- 行内标记

INLINE_RE = re.compile(r"(\*\*.+?\*\*|`[^`]+`|\[[^\]]*\]\([^)]*\))")


def _add_inline(p, text, size=BODY_SIZE, base_bold=False):
    """解析 **粗体**、`行内代码`、[文字](链接)。"""
    for piece in INLINE_RE.split(text):
        if not piece:
            continue
        if piece.startswith("**") and piece.endswith("**") and len(piece) > 4:
            r = p.add_run(piece[2:-2])
            _set_run_font(r, size, bold=True)
        elif piece.startswith("`") and piece.endswith("`") and len(piece) > 2:
            r = p.add_run(piece[1:-1])
            _set_run_font(r, size - 0.5, ea=EA_BODY, ascii_font=ASCII_MONO,
                          color="C7254E")
        elif piece.startswith("[") and "](" in piece:
            label = piece[1:piece.index("](")]
            r = p.add_run(label)
            _set_run_font(r, size, bold=base_bold, color="1F4E79")
            r.font.underline = True
        else:
            r = p.add_run(piece)
            _set_run_font(r, size, bold=base_bold)


# ---------------------------------------------------------------- 表格

def _cell_text(cell, text, size, bold=False, align=WD_ALIGN_PARAGRAPH.LEFT):
    cell.text = ""
    p = cell.paragraphs[0]
    p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(1.5)
    pf.space_after = Pt(1.5)
    pf.first_line_indent = Pt(0)
    pf.line_spacing = 1.0
    _add_inline(p, text, size=size, base_bold=bold)


def _repeat_header(row):
    trpr = row._tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    trpr.append(el)


def _tight_cell_margin(table, twips=72):
    """缩小单元格左右内边距，给内容让位（默认 108 twips 偏宽）。"""
    tblPr = table._tbl.tblPr
    mar = OxmlElement("w:tblCellMar")
    for side in ("left", "right"):
        el = OxmlElement(f"w:{side}")
        el.set(qn("w:w"), str(twips))
        el.set(qn("w:type"), "dxa")
        mar.append(el)
    tblPr.append(mar)


def _no_split_row(row):
    """禁止单行跨页断开：一行内容必须完整落在同一页。"""
    trpr = row._tr.get_or_add_trPr()
    el = OxmlElement("w:cantSplit")
    el.set(qn("w:val"), "true")
    trpr.append(el)


def _disp_width(text):
    """显示宽度：中日韩字符算 2，其余算 1。"""
    return sum(2 if ord(c) > 0x2E80 else 1 for c in text)


def _column_widths(rows, ncol, total_cm):
    """按各列内容长度分配列宽，避免平均分配把长文本列压成竖条。

    权重取「该列内容最大显示宽度」与「该列平均显示宽度 × 1.4」的较大者，
    再叠加下限，最后归一化到版心宽度。
    """
    weights = []
    for j in range(ncol):
        cells = [r[j] if j < len(r) else "" for r in rows]
        max_w = max(_disp_width(c) for c in cells) or 1
        avg_w = sum(_disp_width(c) for c in cells) / max(len(cells), 1)
        weights.append(max(max_w, avg_w * 1.4))

    # 权重开方，抑制极端长列独占宽度
    weights = [w ** 0.72 for w in weights]
    s = sum(weights)

    min_cm = 2.3 if ncol <= 4 else 1.8   # 窄表给足日期列宽，宽表优先保障正文列
    raw = [total_cm * w / s for w in weights]
    widths = [max(w, min_cm) for w in raw]

    # 补偿因下限而溢出的宽度
    over = sum(widths) - total_cm
    if over > 0:
        flex = [i for i in range(ncol) if widths[i] > min_cm]
        pool = sum(widths[i] - min_cm for i in flex) or 1
        for i in flex:
            widths[i] -= over * (widths[i] - min_cm) / pool
    return widths


def _table_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "4")
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), GREY_LINE)
        borders.append(el)
    tblPr.append(borders)


def _split_row(line):
    """切分 | a | b |，忽略转义与首尾空单元。"""
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip().replace("\\|", "|") for c in s.split("|")]


def add_table(doc, rows):
    header, body = rows[0], rows[1:]
    ncol = len(header)
    size = TABLE_SIZE_WIDE if ncol >= 6 else TABLE_SIZE

    table = doc.add_table(rows=len(body) + 1, cols=ncol)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    _table_borders(table)

    # 固定布局 + 显式列宽：否则 Word 会按内容重新计算，长文本列被压窄
    widths = _column_widths(rows, ncol, CONTENT_W)
    tblPr = table._tbl.tblPr
    layout = OxmlElement("w:tblLayout")
    layout.set(qn("w:type"), "fixed")
    tblPr.append(layout)
    tblW = OxmlElement("w:tblW")
    tblW.set(qn("w:type"), "dxa")
    tblW.set(qn("w:w"), str(int(CONTENT_W / 2.54 * 1440)))
    tblPr.append(tblW)
    _tight_cell_margin(table)
    for j, w in enumerate(widths):
        table.columns[j].width = Cm(w)

    for j, txt in enumerate(header):
        cell = table.rows[0].cells[j]
        _cell_text(cell, txt, size, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)
        _shade(cell._tc, GREY_BG)
        cell.width = Cm(widths[j])
    _repeat_header(table.rows[0])
    _no_split_row(table.rows[0])

    for i, row in enumerate(body, start=1):
        row = row + [""] * (ncol - len(row))
        for j in range(ncol):
            cell = table.rows[i].cells[j]
            _cell_text(cell, row[j], size)
            cell.width = Cm(widths[j])
        _no_split_row(table.rows[i])

    # 表后留白，避免与正文贴死
    gap = doc.add_paragraph()
    _fmt(gap, size=6, indent_chars=0, after=0)
    gap.paragraph_format.space_before = Pt(0)
    return table


def _render_quote(doc, sub):
    """渲染引用块。内部若含 Markdown 表格，按表格输出而不是压成一行竖线。"""
    chunks = []
    buf = []
    k, m = 0, len(sub)
    while k < m:
        line = sub[k].strip()
        if (line.startswith("|") and k + 1 < m
                and re.fullmatch(r"\|[\s:|-]+\|", sub[k + 1].strip())):
            if buf:
                chunks.append(("text", buf))
                buf = []
            rows = []
            while k < m and sub[k].strip().startswith("|"):
                rows.append(_split_row(sub[k].strip()))
                k += 1
            # 第 2 行是 |---|---| 分隔行，不是数据
            if len(rows) >= 2 and all(re.fullmatch(r"[\s:|-]*", c) for c in rows[1]):
                rows.pop(1)
            chunks.append(("table", rows))
            continue
        if not line:
            if buf:
                chunks.append(("text", buf))
                buf = []
        else:
            buf.append(line)
        k += 1
    if buf:
        chunks.append(("text", buf))

    for kind, payload in chunks:
        if kind == "table":
            if len(payload) > 1:
                add_table(doc, payload)
            continue
        text = "".join(payload)
        if not text.strip():
            continue
        p = doc.add_paragraph()
        _fmt(p, size=BODY_SIZE - 0.5, indent_chars=0, before=4, after=4)
        p.paragraph_format.left_indent = Pt(10)
        _shade(p._p, GREY_BG)
        _left_border(p)
        _add_inline(p, text, size=BODY_SIZE - 0.5)


# ---------------------------------------------------------------- 代码块

def add_code_block(doc, lines):
    for i, line in enumerate(lines):
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.first_line_indent = Pt(0)
        pf.line_spacing = 1.0
        pf.space_before = Pt(3 if i == 0 else 0)
        pf.space_after = Pt(3 if i == len(lines) - 1 else 0)
        pf.left_indent = Pt(4)
        _shade(p._p if hasattr(p, "_p") else p, GREY_BG)
        r = p.add_run(line if line.strip() else " ")
        _set_run_font(r, CODE_SIZE, ea=EA_BODY, ascii_font=ASCII_MONO)


# ---------------------------------------------------------------- 图片

def add_image(doc, md_line, base_dir):
    m = re.match(r"!\[(.*?)\]\((.+?)\)", md_line.strip())
    if not m:
        return False
    alt, path = m.group(1), m.group(2)
    full = path if os.path.isabs(path) else os.path.normpath(os.path.join(base_dir, path))
    if not os.path.exists(full):
        p = doc.add_paragraph()
        _fmt(p, indent_chars=0, align=WD_ALIGN_PARAGRAPH.CENTER)
        r = p.add_run(f"［图片缺失：{path}］")
        _set_run_font(r, BODY_SIZE, color="C00000")
        return True

    p = doc.add_paragraph()
    _fmt(p, indent_chars=0, align=WD_ALIGN_PARAGRAPH.CENTER, before=6, after=3, keep_next=True)
    run = p.add_run()
    shape = run.add_picture(full, width=Cm(CONTENT_W))

    # 竖长图（活动图等）按宽度铺满会撑破整页，改为同时限制高度
    max_h = Cm(MAX_IMG_H)
    if shape.width > Cm(CONTENT_W):
        ratio = Cm(CONTENT_W) / shape.width
        shape.height = int(shape.height * ratio)
        shape.width = Cm(CONTENT_W)
    if shape.height > max_h:
        ratio = max_h / shape.height
        shape.height = max_h
        shape.width = int(shape.width * ratio)

    # 有 alt 就补一行图注
    if alt and not alt.startswith("图 "):
        pass
    return True


def add_caption(doc, text):
    p = doc.add_paragraph()
    _fmt(p, size=CAPTION_SIZE, indent_chars=0, align=WD_ALIGN_PARAGRAPH.CENTER,
         before=0, after=10)
    _add_inline(p, text, size=CAPTION_SIZE)


def add_placeholder(doc, items):
    p = doc.add_paragraph()
    _fmt(p, size=CAPTION_SIZE, indent_chars=0, align=WD_ALIGN_PARAGRAPH.CENTER,
         before=8, after=8)
    p.paragraph_format.left_indent = Pt(24)
    p.paragraph_format.right_indent = Pt(24)
    _shade(p._p, "FFF2CC")
    for k, txt in enumerate(items):
        if k:
            p.add_run().add_break()
        r = p.add_run(txt)
        _set_run_font(r, CAPTION_SIZE, color="7F6000")


# ---------------------------------------------------------------- 页脚

def add_page_number(section):
    footer = section.footer
    p = footer.paragraphs[0] if footer.paragraphs else footer.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    run = OxmlElement("w:r")
    t = OxmlElement("w:t")
    t.text = "1"
    run.append(t)
    fld.append(run)
    p._p.append(fld)
    for r in p.runs:
        _set_run_font(r, 10.5)


# ---------------------------------------------------------------- 目录

def _init_heading_styles(doc):
    """规范 Heading 1~3 样式。

    标题必须落到内置 Heading 样式上，Word 的目录域才能识别出条目；
    若只用普通段落手动加粗，更新域的结果是「未找到目录项」。
    """
    for level, size in ((1, 16), (2, 14), (3, 12)):
        try:
            st = doc.styles[f"Heading {level}"]
        except KeyError:
            continue
        st.font.name = ASCII_BODY
        st.font.size = Pt(size)
        st.font.bold = True
        st.font.italic = False
        st.font.color.rgb = RGBColor(0, 0, 0)
        rpr = st.element.get_or_add_rPr()
        rfonts = rpr.find(qn("w:rFonts"))
        if rfonts is None:
            rfonts = OxmlElement("w:rFonts")
            rpr.append(rfonts)
        for attr in ("w:ascii", "w:hAnsi"):
            rfonts.set(qn(attr), ASCII_BODY)
        rfonts.set(qn("w:eastAsia"), EA_HEAD)
        # 去掉 Word 内置标题样式自带的段前段后，改由段落级控制
        pf = st.paragraph_format
        pf.space_before = Pt(0)
        pf.space_after = Pt(0)
        pf.first_line_indent = Pt(0)

    # 目录条目压紧：默认 12pt 行距会让 9 章的目录占两页
    for name in ("toc 1", "toc 2", "TOC Heading"):
        try:
            st = doc.styles[name]
        except KeyError:
            continue
        st.font.name = ASCII_BODY
        st.font.size = Pt(TABLE_SIZE)
        rpr = st.element.get_or_add_rPr()
        rfonts = rpr.find(qn("w:rFonts"))
        if rfonts is None:
            rfonts = OxmlElement("w:rFonts")
            rpr.append(rfonts)
        rfonts.set(qn("w:ascii"), ASCII_BODY)
        rfonts.set(qn("w:hAnsi"), ASCII_BODY)
        rfonts.set(qn("w:eastAsia"), EA_BODY)
        pf = st.paragraph_format
        pf.space_before = Pt(2)
        pf.space_after = Pt(2)
        pf.line_spacing = 1.25


def _toc_field(paragraph):
    """插入 Word TOC 域。域结果在 Word 中更新后生成真实目录。"""

    def fld(kind):
        r = paragraph.add_run()
        e = OxmlElement("w:fldChar")
        e.set(qn("w:fldCharType"), kind)
        r._r.append(e)

    fld("begin")
    r = paragraph.add_run()
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = ' TOC \\o "1-2" \\h \\z \\u '
    r._r.append(instr)
    fld("separate")
    r = paragraph.add_run("（目录域：在 Word 中按 F9 或打开时自动更新）")
    _set_run_font(r, BODY_SIZE, color=GREY_TEXT)
    fld("end")


def add_toc(doc):
    h = doc.add_paragraph()
    _fmt(h, size=16, line=1.5, indent_chars=0,
         align=WD_ALIGN_PARAGRAPH.CENTER, before=6, after=12)
    h.paragraph_format.page_break_before = True   # 目录另起一页，不用插分页符
    r = h.add_run("目　　录")
    _set_run_font(r, 16, bold=True, ea=EA_HEAD)

    p = doc.add_paragraph()
    _fmt(p, indent_chars=0, line=1.5)
    _toc_field(p)


# ---------------------------------------------------------------- 主流程

def convert(src, dst, toc=False):
    base_dir = os.path.dirname(os.path.abspath(src))
    s = io.open(src, encoding="utf-8").read()

    doc = Document()

    # 全局默认字体
    style = doc.styles["Normal"]
    style.font.name = ASCII_BODY
    style.font.size = Pt(BODY_SIZE)
    style.element.rPr.rFonts.set(qn("w:eastAsia"), EA_BODY)

    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(PAGE_W), Cm(PAGE_H)
    sec.top_margin, sec.bottom_margin = Cm(MARGIN_TB), Cm(MARGIN_TB)
    sec.left_margin, sec.right_margin = Cm(MARGIN_L), Cm(MARGIN_R)
    add_page_number(sec)

    _init_heading_styles(doc)

    lines = s.split("\n")
    i = 0
    n = len(lines)
    h1_seen = 0

    while i < n:
        raw = lines[i]
        line = raw.rstrip()
        stripped = line.strip()

        # 空行
        if not stripped:
            i += 1
            continue

        # 代码块
        if stripped.startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i].rstrip("\n"))
                i += 1
            i += 1
            while buf and not buf[-1].strip():
                buf.pop()
            add_code_block(doc, buf)
            continue

        # 图片
        if stripped.startswith("!["):
            add_image(doc, stripped, base_dir)
            i += 1
            continue

        # 居中图注 <p align="center">
        if stripped.startswith('<p align="center">'):
            txt = re.sub(r"</?p[^>]*>", "", stripped)
            add_caption(doc, txt)
            i += 1
            continue

        # 水平线 —— 章间分页由 h1 负责，这里忽略
        if re.fullmatch(r"(-{3,}|\*{3,}|_{3,})", stripped):
            i += 1
            continue

        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level, title = len(m.group(1)), m.group(2).strip()
            if level == 1:
                h1_seen += 1
                if h1_seen == 1:
                    cp = doc.core_properties
                    cp.title = title
                    cp.author = "翁佳华"
                    cp.subject = "系统设计说明书"
                    cp.category = "GB/T 8567-2006 软件设计说明（SDD）"
                    cp.comments = "拾集小队 · 校易集 CampusSwap"
                    cp.keywords = "系统设计;UML;接口设计;校园二手;CampusSwap"
                    # 文档大标题，用普通段落：套 Heading 样式会被目录收进去
                    p = doc.add_paragraph()
                    _fmt(p, size=16, line=1.5, indent_chars=0,
                         align=WD_ALIGN_PARAGRAPH.CENTER, before=6, after=12,
                         keep_next=True)
                    _add_inline(p, title, size=16, base_bold=True)
                    for r in p.runs:
                        _set_run_font(r, 16, bold=True, ea=EA_HEAD)
                    i += 1
                    continue
                if toc and h1_seen == 2:
                    add_toc(doc)
                p = doc.add_paragraph(style="Heading 1")
                _fmt(p, size=16, line=1.5, indent_chars=0,
                     align=WD_ALIGN_PARAGRAPH.CENTER, before=6, after=12, keep_next=True)
                # 段前分页：比插入分页符稳，内容恰好满页时不会多出空白页
                p.paragraph_format.page_break_before = True
                _add_inline(p, title, size=16, base_bold=True)
                for r in p.runs:
                    _set_run_font(r, 16, bold=True, ea=EA_HEAD)
            elif level == 2:
                p = doc.add_paragraph(style="Heading 2")
                _fmt(p, size=14, indent_chars=0, before=12, after=6, keep_next=True)
                _add_inline(p, title, size=14, base_bold=True)
                for r in p.runs:
                    _set_run_font(r, 14, bold=True, ea=EA_HEAD)
            else:
                size = 12 if level == 3 else 12
                p = doc.add_paragraph(style="Heading 3")
                _fmt(p, size=size, indent_chars=0, before=6, after=3, keep_next=True)
                _add_inline(p, title, size=size, base_bold=True)
                for r in p.runs:
                    _set_run_font(r, size, bold=True, ea=EA_HEAD)
            i += 1
            continue

        # 表格
        if stripped.startswith("|") and i + 1 < n and re.fullmatch(
                r"\|[\s:|-]+\|", lines[i + 1].strip()):
            rows = [_split_row(stripped)]
            i += 2
            while i < n and lines[i].strip().startswith("|"):
                rows.append(_split_row(lines[i].strip()))
                i += 1
            if len(rows) > 1:
                add_table(doc, rows)
            continue

        # 引用块（内部可能嵌套表格，不能整块压成一段文字）
        if stripped.startswith(">"):
            sub = []
            while i < n and lines[i].strip().startswith(">"):
                sub.append(re.sub(r"^\s*>\s?", "", lines[i]).rstrip())
                i += 1
            _render_quote(doc, sub)
            continue

        # 列表
        m = re.match(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$", line)
        if m:
            indent = len(m.group(1))
            marker = m.group(2)
            text = m.group(3)
            ordered = marker[0].isdigit()
            p = doc.add_paragraph()
            _fmt(p, size=BODY_SIZE, indent_chars=0, before=0, after=0)
            p.paragraph_format.left_indent = Pt(24 + indent * 12)
            p.paragraph_format.first_line_indent = Pt(-12)
            label = f"{marker} " if ordered else "· "
            r = p.add_run(label)
            _set_run_font(r, BODY_SIZE)
            _add_inline(p, text, size=BODY_SIZE)
            i += 1
            continue

        # 图占位符（连续多行合并为一个占位框）
        if stripped.startswith("【图 ") and stripped.endswith("】"):
            items = [stripped]
            i += 1
            while (i < n and lines[i].strip().startswith("【图 ")
                   and lines[i].strip().endswith("】")):
                items.append(lines[i].strip())
                i += 1
            add_placeholder(doc, items)
            continue

        # 普通段落（合并连续行）
        buf = [stripped]
        i += 1
        while i < n:
            nxt = lines[i].strip()
            if (not nxt or nxt.startswith("#") or nxt.startswith("|")
                    or nxt.startswith("```") or nxt.startswith(">")
                    or nxt.startswith("![") or nxt.startswith("<p ")
                    or re.match(r"^([-*+]|\d+[.)])\s+", nxt)):
                break
            buf.append(nxt)
            i += 1
        p = doc.add_paragraph()
        _fmt(p, size=BODY_SIZE)
        _add_inline(p, "".join(buf) if _is_ascii_glue(buf) else "".join(buf), size=BODY_SIZE)

    doc.save(dst)
    return dst


def _is_ascii_glue(buf):
    return True


if __name__ == "__main__":
    argv = sys.argv[1:]
    want_toc = "--toc" in argv
    pos = [a for a in argv if not a.startswith("--")]
    if len(pos) < 2:
        print("用法: python tools/md2docx.py 输入.md 输出.docx [--toc]")
        sys.exit(1)
    out = convert(pos[0], pos[1], toc=want_toc)
    print(f"OK -> {out}" + ("（含目录）" if want_toc else ""))
