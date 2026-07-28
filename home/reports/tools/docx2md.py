#!/usr/bin/env python3
"""docx → Markdown. Обратная операция к md2docx.py.

Нужен для двух вещей:
  1) вернуть в архив исходник .md для отчёта, который был собран без него;
  2) прочитать входящий .docx (например, календарь разработки от CEO), когда
     на сервере нет ни pandoc, ни python-docx.

Восстанавливает структуру, а не только текст: Heading1/Heading2 → ## / ###,
таблицы → GFM, жирный → **, крупный титул → #, подзаголовок → >.

Использование:
    python3 docx2md.py файл.docx [out.md]
    python3 docx2md.py файл.docx -        # печать в stdout
"""
import re
import sys
import zipfile
from html import unescape
from pathlib import Path

P_RE = re.compile(r'<w:p\b.*?</w:p>|<w:p\b[^>]*/>', re.S)
TBL_RE = re.compile(r'<w:tbl>.*?</w:tbl>', re.S)
BLOCK_RE = re.compile(r'<w:tbl>.*?</w:tbl>|<w:p\b.*?</w:p>|<w:p\b[^>]*/>', re.S)
ROW_RE = re.compile(r'<w:tr\b.*?</w:tr>', re.S)
CELL_RE = re.compile(r'<w:tc>.*?</w:tc>', re.S)
RUN_RE = re.compile(r'<w:r>(?:(?!</w:r>).)*</w:r>', re.S)


def run_text(run_xml):
    parts = re.findall(r'<w:t[^>]*>(.*?)</w:t>', run_xml, re.S)
    text = unescape(''.join(parts))
    if not text:
        return ''
    is_bold = '<w:b/>' in run_xml or '<w:b ' in run_xml
    return f'**{text}**' if is_bold and text.strip() else text


def para_text(p_xml):
    text = ''.join(run_text(r) for r in RUN_RE.findall(p_xml))
    # склеиваем соседние жирные куски: **а****б** → **аб**
    return re.sub(r'\*\*\*\*', '', text).strip()


def para_meta(p_xml):
    style = re.search(r'<w:pStyle w:val="([^"]+)"', p_xml)
    size = re.search(r'<w:sz w:val="(\d+)"', p_xml)
    color = re.search(r'<w:color w:val="([0-9A-Fa-f]{6})"', p_xml)
    numbered = '<w:numPr>' in p_xml
    return (style.group(1) if style else None,
            int(size.group(1)) if size else None,
            color.group(1) if color else None,
            numbered)


def convert_paragraph(p_xml):
    text = para_text(p_xml)
    if not text:
        return None
    style, size, color, numbered = para_meta(p_xml)
    clean = text.replace('**', '') if size and size >= 30 else text

    if style == 'Heading1':
        return f'## {clean}'
    if style == 'Heading2':
        return f'### {clean}'
    if numbered or style == 'ListParagraph':
        return f'- {text}'
    if size and size >= 30:                       # титул документа
        return f'# {clean}'
    if size and size <= 24 and color:             # подзаголовок под титулом
        return f'> {clean}'
    return text


def convert_table(tbl_xml):
    rows = []
    for row_xml in ROW_RE.findall(tbl_xml):
        cells = []
        for cell_xml in CELL_RE.findall(row_xml):
            paras = [para_text(p) for p in P_RE.findall(cell_xml)]
            paras = [p for p in paras if p]
            cells.append('<br>'.join(paras))
        if cells:
            rows.append(cells)
    if not rows:
        return None
    ncols = len(rows[0])
    header = [c.replace('**', '') for c in rows[0]]   # шапка жирная по стилю, разметка не нужна
    out = ['| ' + ' | '.join(header) + ' |',
           '|' + '---|' * ncols]
    for row in rows[1:]:
        row = (row + [''] * ncols)[:ncols]
        out.append('| ' + ' | '.join(row) + ' |')
    return '\n'.join(out)


def convert(docx_path):
    doc = zipfile.ZipFile(docx_path).read('word/document.xml').decode('utf-8')
    body = doc[doc.index('<w:body>'):]
    chunks = []
    for block in BLOCK_RE.findall(body):
        piece = convert_table(block) if block.startswith('<w:tbl>') else convert_paragraph(block)
        if piece:
            chunks.append(piece)
    return '\n\n'.join(chunks) + '\n'


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    md = convert(src)
    if len(sys.argv) > 2 and sys.argv[2] != '-':
        Path(sys.argv[2]).write_text(md, encoding='utf-8')
        print(f'OK -> {sys.argv[2]}')
    else:
        print(md)


if __name__ == '__main__':
    main()
