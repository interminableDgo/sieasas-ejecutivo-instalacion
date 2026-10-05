"""Native, editable Excel presentation of the aggregate Executive report."""
import io
import math
import textwrap
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from openpyxl import Workbook
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.chart.label import DataLabelList
from openpyxl.chart.text import RichText
from openpyxl.drawing.line import LineProperties
from openpyxl.drawing.spreadsheet_drawing import AnchorMarker, TwoCellAnchor
from openpyxl.drawing.text import CharacterProperties, Font as DrawingFont, Paragraph, ParagraphProperties
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.pagebreak import Break
from openpyxl.worksheet.page import PageMargins

ORANGE, BLUE, INK, MUTED = 'FF8200', '16A5D8', '292D32', '62676C'
TITLES = ['Municipios con más solicitudes', 'Apoyos más solicitados',
          'Dependencias que remiten más solicitudes', 'Grupos registrados con más solicitudes']


def chart_text(size=11):
    return RichText(p=[Paragraph(pPr=ParagraphProperties(
        defRPr=CharacterProperties(latin=DrawingFont(typeface='Arial'), sz=size*100)))])


def major_step(maximum):
    target = max(1, maximum / 6)
    power = 10 ** math.floor(math.log10(target))
    return next(n * power for n in (1, 2, 5, 10) if n * power >= target)


def chart_rows(height_cm):
    return math.ceil(height_cm * 72 / 2.54 / 22)


def place_chart(sheet, chart, first_row, height_cm):
    """Use cell boundaries, not a physical extent over implicitly sized rows."""
    chart.title.txPr = chart_text(16)
    # Explicit run formatting prevents Excel from retaining its small theme title.
    for paragraph in chart.title.tx.rich.p:
        paragraph.pPr = ParagraphProperties(
            defRPr=CharacterProperties(latin=DrawingFont(typeface='Arial'), sz=1600, b=True))
        for run in paragraph.r:
            run.rPr = CharacterProperties(latin=DrawingFont(typeface='Arial'), sz=1600, b=True)
    chart.title.overlay = False
    last_row = first_row + chart_rows(height_cm)
    for row in range(first_row, last_row + 2):
        sheet.row_dimensions[row].height = 22
    chart.anchor = TwoCellAnchor(
        editAs='twoCell',
        _from=AnchorMarker(col=1, row=first_row-1),
        to=AnchorMarker(col=17, row=last_row-1),
    )
    sheet.add_chart(chart)
    return last_row + 2


def render(report, dimensions, definitions):
    book = Workbook()
    book.remove(book.active)
    stamp = datetime.strptime(report['generated'], '%Y-%m-%d %H:%M UTC').replace(tzinfo=timezone.utc)
    local = stamp.astimezone(ZoneInfo('America/Mexico_City'))
    offset = local.strftime('%z')
    exported = f"{local:%d/%m/%Y, %H:%M} (Ciudad de México, UTC{offset[:3]}:{offset[3:]})"

    def cell(sheet, row, col, value, size=11, bold=False, fill=None):
        c = sheet.cell(row, col, value)
        if isinstance(value, str):
            c.data_type = 's'  # Never interpret catalogue text as a formula.
        c.font = Font(name='Arial', size=size, bold=bold, color=INK)
        c.alignment = Alignment(vertical='center', wrap_text=True)
        if fill:
            c.fill = PatternFill('solid', fgColor=fill)
        return c

    def span(sheet, row, value, size=11, bold=False):
        sheet.merge_cells(start_row=row, start_column=2, end_row=row, end_column=17)
        cell(sheet, row, 2, value, size, bold)

    def base(name, title):
        sheet = book.create_sheet(name)
        sheet.sheet_view.showGridLines = False
        sheet.sheet_view.zoomScale = 85
        sheet.sheet_properties.tabColor = ORANGE
        sheet.sheet_format.defaultRowHeight = 22
        sheet.column_dimensions['A'].width = 3
        for i in range(2, 18):
            sheet.column_dimensions[chr(64+i)].width = 9
        span(sheet, 2, 'SIESAS', 12, True)
        span(sheet, 3, title, 17, True)
        sheet.row_dimensions[3].height = 30
        metadata = [f"Periodo de registro: {report['period']}",
                    f"Entidad: {report['entity']}", f'Exportado: {exported}',
                    *[f'{label}: {value}' for label, value in report['filters']]]
        row = 4
        for value in metadata:
            for line in textwrap.wrap(value, 115) or ['']:
                span(sheet, row, line)
                row += 1
        sheet.row_dimensions[row].height = 8
        for c in sheet[row][1:17]:
            c.border = Border(bottom=Side(style='thin', color='D9DEE3'))
        sheet.print_title_rows = f'1:{row}'
        sheet.page_setup.orientation = 'landscape'
        sheet.page_setup.paperSize = sheet.PAPERSIZE_A4
        sheet.sheet_properties.pageSetUpPr.fitToPage = True
        sheet.page_setup.fitToWidth = 1
        sheet.page_setup.fitToHeight = 0
        sheet.page_margins = PageMargins(left=.25, right=.25, top=.35, bottom=.35, header=.15, footer=.15)
        sheet.oddFooter.center.text = 'SIESAS · Página &P de &N'
        return sheet, row + 2

    def table(sheet, start, headers, rows):
        # Presentation grid: wide category B:M, count N:O, share P:Q.
        for j, value in enumerate(headers):
            col, end = [(2, 13), (14, 15), (16, 17)][j]
            sheet.merge_cells(start_row=start, start_column=col, end_row=start, end_column=end)
            cell(sheet, start, col, value, bold=True, fill=ORANGE)
        sheet.row_dimensions[start].height = 30
        for n, values in enumerate(rows, start+1):
            for j, value in enumerate(values):
                col, end = [(2, 13), (14, 15), (16, 17)][j]
                sheet.merge_cells(start_row=n, start_column=col, end_row=n, end_column=end)
                c = cell(sheet, n, col, value, fill='F5F6F7' if (n-start)%2 else 'FFFFFF')
                if j:
                    c.number_format = '0.0%' if j == 2 and headers[2] == '% del total' else '#,##0'
                    c.alignment = Alignment(horizontal='right', vertical='center')
            sheet.row_dimensions[n].height = max(24, 16 * math.ceil(len(str(values[0]))/85))
        return start + len(rows)

    def bars(sheet, title, rows, anchor, helper):
        if not rows or not report['total']:
            return 0
        # Source ranges sit below all visible data, never overwrite a large table.
        for i, (label, count) in enumerate(reversed(rows), helper):
            cell(sheet, i, 2, label)
            cell(sheet, i, 3, count)
        c = BarChart()
        c.type = 'bar'
        c.title = title
        c.add_data(Reference(sheet, min_col=3, min_row=helper, max_row=helper+len(rows)-1))
        c.set_categories(Reference(sheet, min_col=2, min_row=helper, max_row=helper+len(rows)-1))
        c.legend = None
        # openpyxl calls the numeric axis y_axis even for horizontal bars.
        c.y_axis.scaling.min = 0
        c.y_axis.numFmt = '#,##0'
        c.y_axis.majorUnit = major_step(max(n for _, n in rows))
        c.x_axis.txPr = chart_text()
        c.y_axis.txPr = chart_text()
        c.x_axis.delete = False
        c.y_axis.delete = False
        c.x_axis.majorGridlines = None
        c.y_axis.majorGridlines = None
        c.series[0].graphicalProperties.solidFill = ORANGE
        c.series[0].graphicalProperties.line.noFill = True
        c.dLbls = DataLabelList()
        c.dLbls.showVal = True
        c.dLbls.showSerName = False
        c.dLbls.showCatName = False
        c.dLbls.showLegendKey = False
        c.dLbls.showPercent = False
        c.dLbls.showBubbleSize = False
        c.dLbls.dLblPos = 'outEnd'
        c.dLbls.txPr = chart_text()
        c.y_axis.scaling.max = max(x[1] for x in rows)*1.15 or 1
        c.width, c.height = 28, max(5, len(rows)*.85+2)
        c.gapWidth = 65
        return place_chart(sheet, c, anchor, c.height)

    summary, start = base('Resumen', 'Reporte ejecutivo de solicitudes')
    metrics = [('Solicitudes', report['total']), ('Activas', report['active']),
               ('Resueltas', report['resolved']), ('Otros estatus', report['other']),
               ('Porcentaje resuelto', report['ratio'] if report['ratio'] is not None else 'No aplica')]
    for i, (label, value) in enumerate(metrics):
        col, end = 2+i*3, (4+i*3 if i<4 else 17)
        for row, v, size in [(start, label, 11), (start+1, value, 20)]:
            summary.merge_cells(start_row=row, start_column=col, end_row=row, end_column=end)
            c = cell(summary, row, col, v, size, row==start+1, 'FFF1E5' if row==start+1 else None)
            c.number_format = '0.0%' if i==4 else '#,##0'
            c.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
        summary.row_dimensions[start+1].height = 36
    for column in ('N', 'O', 'P', 'Q'):
        summary.column_dimensions[column].width = 6.75
    span(summary, start+3, 'Se cuentan solicitudes, no personas únicas. Estatus al momento de exportar.')
    status = sorted([(label, value) for label, value in metrics[1:4]], key=lambda x:-x[1])
    # Helpers assigned after visible notes.
    note = start+5+chart_rows(5)+2
    span(summary, note, 'Definiciones y alcance', 13, True)
    for label, description in definitions:
        for line in textwrap.wrap(f'{label}: {description}', 115):
            note += 1
            span(summary, note, line)
    bars(summary, 'Solicitudes por estatus actual', status, start+5, note+4)
    if not report['total']:
        span(summary, start+5, 'Sin resultados para el periodo y filtros seleccionados.')
    summary.print_area = f'B2:Q{note}'

    trend, start = base('Tendencia', 'Solicitudes por mes de registro')
    span(trend, start, 'Las resueltas pertenecen al mes de registro; no indican fecha de resolución.')
    table_row = start+2+chart_rows(14)+2 if report['trend'] and report['total'] else start+3
    end = table(trend, table_row, ['Mes de registro', 'Registradas', 'Resueltas actualmente'], report['trend'])
    if report['trend'] and report['total']:
        c = LineChart()
        c.title = 'Evolución mensual de solicitudes'
        from openpyxl.chart import Series
        for col, name, color, dash in [(14, 'Registradas', BLUE, 'solid'), (16, 'Resueltas actualmente', ORANGE, 'dash')]:
            series = Series(Reference(trend, min_col=col, min_row=table_row+1, max_row=end), title=name)
            series.graphicalProperties.line = LineProperties(solidFill=color, prstDash=dash, w=28575)
            series.smooth = False
            if len(report['trend']) == 1:
                series.marker.symbol = 'circle'
                series.marker.size = 6
            c.append(series)
        c.set_categories(Reference(trend, min_col=2, min_row=table_row+1, max_row=end))
        c.y_axis.scaling.min = 0
        c.y_axis.numFmt = '#,##0'
        c.y_axis.majorUnit = major_step(max(max(row[1:]) for row in report['trend']))
        c.x_axis.txPr = chart_text()
        c.y_axis.txPr = chart_text()
        c.x_axis.delete = False
        c.y_axis.delete = False
        c.x_axis.tickLblSkip = max(1, math.ceil(len(report['trend'])/12))
        c.x_axis.majorGridlines = None
        c.legend.position = 't'
        c.legend.overlay = False
        c.title.overlay = False
        c.legend.txPr = chart_text()
        c.width, c.height = 28, 14
        place_chart(trend, c, start+2, 14)
    else:
        span(trend, start+1, 'Sin resultados')
    trend.print_area = f'B2:Q{end}'
    trend.row_breaks.append(Break(id=table_row-1))

    for index, (key, name) in enumerate(dimensions):
        sheet, start = base(name, 'Solicitudes por '+name.lower())
        rows = sorted(report['groups'][key], key=lambda x:-x[1])
        top = rows[:10]
        coverage = sum(n for _, n in top)/report['total'] if report['total'] else None
        span(sheet, start, (f'Las {len(top)} primeras reúnen {coverage:.1%} del total. '
                           f'Tabla completa: {len(rows)} categorías. Base: {report["total"]:,} solicitudes.')
             if coverage is not None else 'Sin resultados para el periodo y filtros seleccionados.')
        if len(rows)>10 and rows[9][1]==rows[10][1]:
            span(sheet, start+1, 'Empates: se conserva el orden de origen; hay categorías con igual cantidad fuera del top 10.', 10)
        height = max(5, len(top)*.85+2)
        table_row = start+3+chart_rows(height)+2 if top and report['total'] else start+3
        end = table(sheet, table_row, ['Categoría', 'Solicitudes', '% del total'],
                    [(label, count, count/report['total'] if report['total'] else 'No aplica') for label, count in rows])
        bars(sheet, TITLES[index], top, start+3, end+4)
        sheet.auto_filter.ref = f'B{table_row}:Q{end}'
        sheet.freeze_panes = f'B{start}'
        sheet.print_area = f'B2:Q{end}'
        sheet.row_breaks.append(Break(id=table_row-1))

    stream = io.BytesIO()
    book.save(stream)
    return stream.getvalue()
