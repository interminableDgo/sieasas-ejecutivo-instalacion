"""Aggregate-only Executive reports. Renderers never receive request/person rows."""
import io
import textwrap
from datetime import datetime, timezone
from html import escape

from openpyxl import Workbook
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.styles import Alignment, Font, PatternFill
from reportlab.graphics.shapes import Drawing, Rect, String
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
)

INK, ORANGE, BLUE, PAPER, MUTED = '1B2A33', 'FF8300', '12A5E5', 'F3F3F0', '5B6B74'
DIMENSIONS = [('municipios', 'Municipios'), ('apoyos', 'Tipos de apoyo'),
              ('dependencias', 'Dependencias remitentes'), ('grupos', 'Grupos vulnerables')]
FILTER_LABELS = {
    'municipio_id': ('Municipio', 'municipios'),
    'tipo_apoyo_id': ('Tipo de apoyo', 'apoyos'),
    'dependencia_id': ('Dependencia remitente', 'dependencias'),
    'grupo_vulnerable_id': ('Grupo vulnerable', 'grupos'),
    'estatus_id': ('Estatus', 'estatus'),
}
DEFINITIONS = [
    ('Unidad y periodo', 'Se cuentan solicitudes, no personas únicas. El periodo usa la fecha de registro e incluye el día final. Sin fechas se consulta todo el historial autorizado.'),
    ('Estatus', 'Resueltas: Resuelto y Resuelto con observación. Otros estatus: Cerrado / Cancelado y No es competencia. Activas: los demás estatus.'),
    ('Porcentajes', 'Porcentaje resuelto = resueltas / total filtrado × 100. Cada distribución usa el mismo total como base. Sin solicitudes: No aplica.'),
    ('Tendencia', 'Las resueltas pertenecen a la cohorte del mes de registro; no indican resoluciones ocurridas ese mes. Los meses intermedios sin registros se muestran en cero.'),
    ('Alcance', 'Municipio: domicilio del beneficiario. Dependencia: remitente. Sin información: catálogo opcional ausente. Se aplican la entidad autorizada y todos los filtros; las opciones de un mismo filtro son alternativas. Datos al momento de la consulta, sin nombres ni expedientes individuales.'),
]


def build_report(summary, user, selected, catalogs, generated_at=None):
    """Explicit allowlist prevents extra fields in service responses leaking to files."""
    total = int(summary['total'])
    resolved, active = int(summary['resueltas']), int(summary['activas'])
    filters = []
    for key, (label, catalog) in FILTER_LABELS.items():
        if key not in selected:
            continue
        ids = selected[key] if isinstance(selected[key], list) else [selected[key]]
        names = {row['id']: row['nombre'] for row in catalogs.get(catalog, [])}
        filters.append((label, ', '.join(str(names.get(i, f'Clave {i} (sin etiqueta disponible)')) for i in ids)))
    start, end = selected.get('fecha_inicio'), selected.get('fecha_fin')
    period = (f"{start or 'Sin límite inicial'} al {end or 'Sin límite final'}"
              if start or end else 'Todo el historial (sin límite de fechas)')
    return {
        'entity': str(user['entidad']), 'period': period,
        'generated': (generated_at or datetime.now(timezone.utc)).strftime('%Y-%m-%d %H:%M UTC'),
        'filters': filters or [('Filtros', 'Sin filtros adicionales')],
        'total': total, 'resolved': resolved, 'active': active,
        'other': total - resolved - active,
        'ratio': resolved / total if total else None,
        'groups': {key: [(str(r['nombre']), int(r['total'])) for r in summary[key]] for key, _ in DIMENSIONS},
        'trend': [(str(r['mes']), int(r['recibidas']), int(r['resueltas'])) for r in summary['tendencia']],
    }


def render_xlsx(report):
    book = Workbook()
    summary = book.active
    summary.title = 'Resumen'

    def append(sheet, values):
        sheet.append(values)
        for cell in sheet[sheet.max_row]:
            # Catalog labels are text, even when starting with '=' or other formula prefixes.
            if isinstance(cell.value, str):
                cell.data_type = 's'
            cell.font = Font(name='Calibri', size=11, color=INK)
            cell.alignment = Alignment(vertical='top', wrap_text=True)
        sheet.row_dimensions[sheet.max_row].height = 25

    def heading(sheet, title):
        append(sheet, [title])
        sheet.merge_cells(start_row=sheet.max_row, start_column=1, end_row=sheet.max_row, end_column=3)
        cell = sheet.cell(sheet.max_row, 1)
        cell.font = Font(name='Calibri', size=18, bold=True, color=INK)
        sheet.row_dimensions[sheet.max_row].height = 42

    def table_header(sheet, values):
        append(sheet, values)
        for cell in sheet[sheet.max_row]:
            cell.fill = PatternFill('solid', fgColor='EEF3F6')
            cell.font = Font(name='Calibri', color=INK, bold=True)

    heading(summary, 'SIESAS | Reporte ejecutivo')
    for row in [('Entidad', report['entity']), ('Periodo de registro', report['period']),
                ('Generado', report['generated']), *report['filters']]:
        lines = textwrap.wrap(str(row[1]), width=52) or ['']
        # Split large multi-select descriptions before Excel's row-height limit.
        for offset in range(0, len(lines), 3):
            chunk = lines[offset:offset + 3]
            append(summary, [row[0] if offset == 0 else 'Continuación', '\n'.join(chunk)])
            summary.merge_cells(start_row=summary.max_row, start_column=2, end_row=summary.max_row, end_column=3)
            summary.row_dimensions[summary.max_row].height = max(34, 16 * len(chunk) + 10)
    append(summary, [])
    table_header(summary, ['Indicador', 'Valor', 'Unidad'])
    for label, value, unit in [('Solicitudes', report['total'], 'solicitudes'),
                             ('Activas', report['active'], 'solicitudes'),
                             ('Resueltas actualmente', report['resolved'], 'solicitudes'),
                             ('Otros estatus', report['other'], 'solicitudes'),
                             ('Porcentaje resuelto', report['ratio'] if report['ratio'] is not None else 'No aplica', '% del total')]:
        append(summary, [label, value, unit])
    if report['ratio'] is not None:
        summary.cell(summary.max_row, 2).number_format = '0.0%'
    append(summary, [])
    if not report['total']:
        append(summary, ['Sin resultados', 'No hay solicitudes para el periodo y filtros seleccionados.'])
    heading(summary, 'Notas de lectura')
    for label, description in DEFINITIONS:
        lines = textwrap.wrap(description, width=52)
        append(summary, [label, '\n'.join(lines)])
        summary.merge_cells(start_row=summary.max_row, start_column=2, end_row=summary.max_row, end_column=3)
        summary.row_dimensions[summary.max_row].height = max(45, 16 * len(lines) + 10)

    trend = book.create_sheet('Tendencia')
    heading(trend, 'Tendencia por mes de registro')
    append(trend, ['Periodo', report['period']])
    append(trend, ['Lectura', 'Resueltas actualmente por cohorte de registro; no es fecha de resolución.'])
    trend.merge_cells('B3:C3')
    trend.row_dimensions[3].height = 45
    table_header(trend, ['Mes de registro', 'Registradas', 'Resueltas actualmente'])
    for row in report['trend']:
        append(trend, list(row))
    # Separate charts keep labels legible even for multi-year reports; no rows are omitted.
    if report['total']:
        for block, start in enumerate(range(5, trend.max_row + 1, 12)):
            end = min(start + 11, trend.max_row)
            chart = LineChart()
            chart.title = f'Tendencia {trend.cell(start, 1).value} a {trend.cell(end, 1).value}'
            for column in [2, 3]:
                from openpyxl.chart import Series
                chart.append(Series(Reference(trend, min_col=column, min_row=start, max_row=end),
                                    title=trend.cell(4, column).value))
            chart.set_categories(Reference(trend, min_col=1, min_row=start, max_row=end))
            chart.y_axis.title = 'Solicitudes'
            chart.y_axis.scaling.min = 0
            chart.width, chart.height = 20, 9
            chart.legend.position = 'b'
            chart.style = 13
            chart.series[0].graphicalProperties.line.solidFill = BLUE
            chart.series[1].graphicalProperties.line.solidFill = ORANGE
            trend.add_chart(chart, f'E{1 + block * 22}')

    for key, title in DIMENSIONS:
        sheet = book.create_sheet(title)
        heading(sheet, title)
        append(sheet, ['Base', report['total'], 'solicitudes filtradas'])
        table_header(sheet, ['Categoría', 'Solicitudes', '% del total'])
        for name, count in report['groups'][key]:
            append(sheet, [name, count, count / report['total'] if report['total'] else 0])
            sheet.cell(sheet.max_row, 3).number_format = '0.0%'
            sheet.row_dimensions[sheet.max_row].height = max(34, 15 * (len(name) // 40 + 1))
        if not report['groups'][key]:
            append(sheet, ['Sin resultados'])
        else:
            sheet.auto_filter.ref = f'A3:C{sheet.max_row}'
            for block, start in enumerate(range(4, sheet.max_row + 1, 12)):
                end = min(start + 11, sheet.max_row)
                chart = BarChart()
                chart.type = 'bar'
                chart.title = title if len(report['groups'][key]) <= 12 else f'{title} ({start - 3}-{end - 3})'
                chart.add_data(Reference(sheet, min_col=2, min_row=start, max_row=end))
                chart.set_categories(Reference(sheet, min_col=1, min_row=start, max_row=end))
                chart.x_axis.title = 'Solicitudes'
                chart.x_axis.scaling.min = 0
                chart.y_axis.reverseOrder = True
                chart.legend = None
                chart.width, chart.height = 20, max(7, (end - start + 1) * .8 + 3)
                chart.style = 13
                chart.series[0].graphicalProperties.solidFill = BLUE
                sheet.add_chart(chart, f'E{1 + block * 32}')

    for sheet in book:
        sheet.sheet_view.showGridLines = False
        sheet.freeze_panes = 'B5' if sheet.title == 'Tendencia' else 'B4'
        sheet.sheet_view.zoomScale = 90
        for column, width in [('A', 46), ('B', 24), ('C', 32)]:
            sheet.column_dimensions[column].width = width
        sheet.sheet_properties.pageSetUpPr.fitToPage = True
        sheet.page_setup.orientation = 'landscape'
        sheet.page_setup.paperSize = sheet.PAPERSIZE_A4
        sheet.page_setup.fitToWidth = 1
        sheet.page_setup.fitToHeight = 0
        sheet.oddFooter.center.text = 'SIESAS | Página &P de &N'
    stream = io.BytesIO()
    book.save(stream)
    return stream.getvalue()


def render_pdf(report):
    stream = io.BytesIO()
    width = A4[0] - 88
    styles = {
        'body': ParagraphStyle('body', fontName='Helvetica', fontSize=9, leading=12, textColor=colors.HexColor('#' + INK), spaceAfter=5),
        'small': ParagraphStyle('small', fontName='Helvetica', fontSize=8, leading=11, textColor=colors.HexColor('#' + MUTED), spaceAfter=4),
        'title': ParagraphStyle('title', fontName='Helvetica-Bold', fontSize=24, leading=28, textColor=colors.HexColor('#' + INK), spaceAfter=8),
        'h': ParagraphStyle('h', fontName='Helvetica-Bold', fontSize=12, leading=16, textColor=colors.HexColor('#' + INK), spaceBefore=12, spaceAfter=7, keepWithNext=True),
        'value': ParagraphStyle('value', fontName='Helvetica-Bold', fontSize=22, leading=26, textColor=colors.HexColor('#' + INK)),
    }

    def p(value, style='body'):
        return Paragraph(escape(str(value)), styles[style])

    def table(rows, widths):
        t = Table(rows, colWidths=widths, repeatRows=1, hAlign='LEFT')
        t.setStyle(TableStyle([
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('LEFTPADDING', (0, 0), (-1, -1), 7), ('RIGHTPADDING', (0, 0), (-1, -1), 7),
            ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#EEF3F6')),
            ('LINEBELOW', (0, 1), (-1, -1), .3, colors.HexColor('#E3E8EB')),
        ]))
        return t

    content = [p('Reporte ejecutivo', 'title'), p(report['entity']),
               p('Periodo de registro: ' + report['period']), p('Generado: ' + report['generated'], 'small')]
    content += [p(f'{label}: {value}', 'small') for label, value in report['filters']]
    values = [('Solicitudes', report['total']), ('Activas', report['active']),
              ('Resueltas', report['resolved']), ('Otros estatus', report['other']),
              ('% resuelto', f"{report['ratio']:.1%}" if report['ratio'] is not None else 'No aplica')]
    indicators = Table([
        [p(label, 'small') for label, _ in values],
        [p(f'{value:,}' if isinstance(value, int) else value, 'value') for _, value in values],
    ], colWidths=[width / 5] * 5)
    indicators.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TOPPADDING', (0, 0), (-1, 0), 12), ('BOTTOMPADDING', (0, -1), (-1, -1), 12),
        ('LINEBELOW', (0, -1), (-1, -1), 1, colors.HexColor('#' + ORANGE)),
    ]))
    content += [Spacer(1, 8), indicators]
    if not report['total']:
        content += [p('Sin resultados para el periodo y filtros seleccionados.', 'h')]
    else:
        for offset in range(0, len(report['trend']), 12):
            rows = report['trend'][offset:offset + 12]
            if offset:
                content.append(PageBreak())
            content += [p('Tendencia mensual', 'h'),
                        p('Azul: registradas. Naranja: resueltas actualmente de esa cohorte.', 'small')]
            maximum = max([r[1] for r in rows] + [1])
            drawing = Drawing(width, len(rows) * 25 + 12)
            for i, (month, received, resolved) in enumerate(rows):
                y = len(rows) * 25 - i * 25
                drawing.add(String(0, y - 2, month, fontName='Helvetica', fontSize=8))
                for delta, count, color in [(0, received, BLUE), (-8, resolved, ORANGE)]:
                    drawing.add(Rect(65, y + delta, count / maximum * (width - 120), 6, fillColor=colors.HexColor('#' + color), strokeColor=None))
                    drawing.add(String(width - 42, y + delta, str(count), fontSize=7, fontName='Helvetica'))
            content += [drawing, p(f'Escala: 0 a {maximum} solicitudes. Mes de registro; no de resolución.', 'small')]

        content.append(PageBreak())
        content += [p('Distribución de solicitudes', 'title'), p(f'Base: {report["total"]:,} solicitudes. Porcentajes sobre el total filtrado.', 'small')]
        for key, title in DIMENSIONS:
            content.append(p(title, 'h'))
            maximum = max([count for _, count in report['groups'][key]] + [1])
            data = [[p('Categoría', 'small'), p('Solicitudes', 'small'), p('Total / %', 'small')]]
            for name, count in report['groups'][key]:
                bar = Drawing(125, 12)
                bar.add(Rect(0, 2, count / maximum * 125, 7, fillColor=colors.HexColor('#' + BLUE), strokeColor=None))
                data.append([p(name), bar, p(f'{count:,} / {count / report["total"]:.1%}')])
            content += [table(data, [width - 240, 140, 100]), p(f'Escala: 0 a {maximum:,} solicitudes.', 'small')]

    content.append(p('Definiciones y alcance', 'h'))
    for label, description in DEFINITIONS:
        content.append(p(f'{label}. {description}', 'small'))

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFillColor(colors.HexColor('#' + ORANGE))
        canvas.rect(44, A4[1] - 35, 20, 3, fill=1, stroke=0)
        canvas.setFillColor(colors.HexColor('#' + INK))
        canvas.setFont('Helvetica-Bold', 9)
        canvas.drawString(73, A4[1] - 37, 'SIESAS')
        canvas.setFillColor(colors.HexColor('#' + MUTED))
        canvas.setFont('Helvetica', 8)
        canvas.drawString(44, 25, report['generated'])
        canvas.drawRightString(A4[0] - 44, 25, str(doc.page))
        canvas.restoreState()

    document = SimpleDocTemplate(stream, pagesize=A4, leftMargin=44, rightMargin=44,
                                 topMargin=58, bottomMargin=45, title='SIESAS | Reporte ejecutivo', author='SIESAS')
    document.build(content, onFirstPage=footer, onLaterPages=footer)
    return stream.getvalue()
