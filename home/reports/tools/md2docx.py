#!/usr/bin/env python3
"""Markdown → docx на каркасе templates/base.docx.

На сервере НЕТ python-docx и pandoc. Документ собирается прямой генерацией
WordprocessingML внутрь копии base.docx: оттуда берутся стили, шрифты,
нумерация и колонтитул, заменяется только word/document.xml.

Поддерживается ровно то, что нужно отчётам:
    # Заголовок        → титул документа (крупный, жирный)
    > Подзаголовок     → строка под титулом (серая), только сразу после титула
    ## Раздел          → Heading1
    ### Подраздел      → Heading2
    - пункт            → маркированный список
    | a | b |          → таблица GFM (первая строка = шапка, вторая = разделитель)
    **жирный**         → жирный внутри абзаца и ячеек
    \n в ячейке        → перенос строки внутри ячейки: пишется как <br>

Ширины колонок таблицы считаются автоматически по длине содержимого
(сумма всегда 9638 twips = ширина полосы набора А4 с полями 2 см).

Использование:
    python3 md2docx.py report.md out.docx [--template base.docx]
"""
import re
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

TOTAL_WIDTH = 9638          # ширина таблицы в twips
TPL_DEFAULT = Path(__file__).resolve().parent.parent / 'templates' / 'base.docx'

CELL_BORDER = (
    '<w:tcBorders>'
    '<w:top w:val="single" w:color="B7C3CC" w:sz="2"/>'
    '<w:left w:val="single" w:color="B7C3CC" w:sz="2"/>'
    '<w:bottom w:val="single" w:color="B7C3CC" w:sz="2"/>'
    '<w:right w:val="single" w:color="B7C3CC" w:sz="2"/>'
    '</w:tcBorders>'
)
CELL_MARGIN = (
    '<w:tcMar>'
    '<w:top w:type="dxa" w:w="60"/><w:left w:type="dxa" w:w="100"/>'
    '<w:bottom w:type="dxa" w:w="60"/><w:right w:type="dxa" w:w="100"/>'
    '</w:tcMar>'
)


def inline_runs(text, base_rpr=''):
    """**жирный** → отдельные ранты. base_rpr — общие свойства (размер/цвет)."""
    out = ''
    for i, part in enumerate(re.split(r'\*\*(.+?)\*\*', text)):
        if not part:
            continue
        bold = '<w:b/><w:bCs/>' if i % 2 else ''
        rpr = f'<w:rPr>{bold}{base_rpr}</w:rPr>' if (bold or base_rpr) else ''
        out += f'<w:r>{rpr}<w:t xml:space="preserve">{escape(part)}</w:t></w:r>'
    return out


def para(text, after=120, size=None, color=None, bold=False):
    rpr = ''
    if size:
        rpr += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    if color:
        rpr = f'<w:color w:val="{color}"/>' + rpr
    if bold:
        body = f'<w:r><w:rPr><w:b/><w:bCs/>{rpr}</w:rPr><w:t xml:space="preserve">{escape(text)}</w:t></w:r>'
    else:
        body = inline_runs(text, rpr)
    return f'<w:p><w:pPr><w:spacing w:after="{after}"/></w:pPr>{body}</w:p>'


def heading(text, level):
    style = 'Heading1' if level == 1 else 'Heading2'
    return (f'<w:p><w:pPr><w:pStyle w:val="{style}"/></w:pPr>'
            f'<w:r><w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>')


def bullet(text, numpr):
    return (f'<w:p><w:pPr><w:pStyle w:val="ListParagraph"/>{numpr}'
            f'<w:spacing w:after="60"/></w:pPr>{inline_runs(text)}</w:p>')


def cell(text, width, header=False):
    shade = '<w:shd w:fill="DCE7EE" w:val="clear"/>' if header else ''
    base = '<w:sz w:val="18"/><w:szCs w:val="18"/>'
    lines = str(text).split('<br>')
    paras = ''
    for line in lines:
        if header:
            runs = f'<w:r><w:rPr><w:b/><w:bCs/>{base}</w:rPr><w:t xml:space="preserve">{escape(line)}</w:t></w:r>'
        else:
            runs = inline_runs(line, base)
        paras += f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>{runs}</w:p>'
    return (f'<w:tc><w:tcPr><w:tcW w:type="dxa" w:w="{width}"/>'
            f'{CELL_BORDER}{shade}{CELL_MARGIN}</w:tcPr>{paras}</w:tc>')


def auto_widths(rows, ncols):
    """Ширины колонок пропорционально длине содержимого, с полом и потолком."""
    weights = []
    for c in range(ncols):
        longest = max(len(str(r[c]).replace('<br>', ' ')) for r in rows if len(r) > c)
        weights.append(max(longest, 8))
    total = sum(weights)
    raw = [max(int(TOTAL_WIDTH * w / total), 900) for w in weights]
    # нормализуем, чтобы сумма ровно совпала с шириной полосы
    drift = TOTAL_WIDTH - sum(raw)
    raw[raw.index(max(raw))] += drift
    return raw


def table(rows):
    ncols = len(rows[0])
    widths = auto_widths(rows, ncols)
    grid = ''.join(f'<w:gridCol w:w="{w}"/>' for w in widths)
    xml = (
        '<w:tbl><w:tblPr>'
        f'<w:tblW w:type="dxa" w:w="{TOTAL_WIDTH}"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:color="auto" w:sz="4"/><w:left w:val="single" w:color="auto" w:sz="4"/>'
        '<w:bottom w:val="single" w:color="auto" w:sz="4"/><w:right w:val="single" w:color="auto" w:sz="4"/>'
        '<w:insideH w:val="single" w:color="auto" w:sz="4"/><w:insideV w:val="single" w:color="auto" w:sz="4"/>'
        '</w:tblBorders></w:tblPr>'
        f'<w:tblGrid>{grid}</w:tblGrid>'
    )
    xml += ('<w:tr><w:trPr><w:tblHeader/></w:trPr>'
            + ''.join(cell(v, w, header=True) for v, w in zip(rows[0], widths)) + '</w:tr>')
    for row in rows[1:]:
        xml += '<w:tr>' + ''.join(cell(v, w) for v, w in zip(row, widths)) + '</w:tr>'
    xml += '</w:tbl>'
    xml += '<w:p><w:pPr><w:spacing w:after="120"/></w:pPr></w:p>'
    return xml


def split_row(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def is_divider(line):
    return bool(re.fullmatch(r'\|[\s:|-]+\|', line.strip()))


def convert(md_text):
    """Markdown → тело документа (последовательность блоков WordprocessingML)."""
    lines = md_text.split('\n')
    body, i, seen_title = [], 0, False

    while i < len(lines):
        line = lines[i].rstrip()
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        # таблица
        if stripped.startswith('|') and i + 1 < len(lines) and is_divider(lines[i + 1]):
            rows = [split_row(stripped)]
            i += 2
            while i < len(lines) and lines[i].strip().startswith('|'):
                rows.append(split_row(lines[i]))
                i += 1
            body.append(table(rows))
            continue

        if stripped.startswith('### '):
            body.append(heading(stripped[4:], 2))
        elif stripped.startswith('## '):
            body.append(heading(stripped[3:], 1))
        elif stripped.startswith('# '):
            body.append(para(stripped[2:], after=60, size=36, bold=True))
            seen_title = True
        elif stripped.startswith('> '):
            after = 240 if seen_title else 120
            body.append(para(stripped[2:], after=after, size=24, color='44546A'))
        elif stripped.startswith('- '):
            body.append(('BULLET', stripped[2:]))
        else:
            body.append(para(stripped))
        i += 1
    return body


def build(md_path, out_path, template=TPL_DEFAULT, title=None):
    md_text = Path(md_path).read_text(encoding='utf-8')
    tpl = zipfile.ZipFile(template)
    tpl_doc = tpl.read('word/document.xml').decode('utf-8')

    head = tpl_doc[:tpl_doc.index('<w:body>') + len('<w:body>')]
    sect = re.search(r'<w:sectPr.*?</w:sectPr>', tpl_doc, re.S).group(0)
    m = re.search(r'<w:pStyle w:val="ListParagraph"/>(<w:numPr>.*?</w:numPr>)', tpl_doc, re.S)
    numpr = m.group(1) if m else ''

    blocks = convert(md_text)
    xml_body = ''.join(bullet(b[1], numpr) if isinstance(b, tuple) else b for b in blocks)
    document = head + xml_body + sect + '</w:body></w:document>'

    if title is None:
        first = next((l.strip()[2:] for l in md_text.split('\n') if l.strip().startswith('# ')), None)
        title = first or Path(out_path).stem

    out = zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED)
    for item in tpl.infolist():
        data = tpl.read(item.filename)
        if item.filename == 'word/document.xml':
            data = document.encode('utf-8')
        elif item.filename == 'docProps/core.xml':
            data = re.sub(r'<dc:title>.*?</dc:title>',
                          f'<dc:title>{escape(title)}</dc:title>',
                          data.decode('utf-8'), flags=re.S).encode('utf-8')
        out.writestr(item, data)
    out.close()
    return out_path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    tpl = TPL_DEFAULT
    if '--template' in sys.argv:
        tpl = Path(sys.argv[sys.argv.index('--template') + 1])
    result = build(args[0], args[1], tpl)
    print(f'OK -> {result}')


if __name__ == '__main__':
    main()
