"""Aggregate-only Executive reports. Renderers never receive request/person rows."""
import io
import math
from pathlib import Path
from datetime import datetime, timezone
from html import escape

from reportlab.graphics.shapes import Drawing, Rect, String, Line, Circle, Wedge
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether,
)
from app.services.executive_chart_style import (
    BLUE, ORANGE, INK, MUTED, PALETTE, DONUT_KEYS, donut_rows, category_total, category_chart_type, treemap_rects,
)

PAPER = 'F3F3F0'
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
    ('Porcentajes', 'Porcentaje resuelto = resueltas / total filtrado × 100. Las distribuciones usan el total filtrado; grupos vulnerables usa la suma de solicitudes clasificadas, incluida Sin información, igual que el tablero. Sin solicitudes: No aplica.'),
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
    from app.services.executive_xlsx import render
    return render(report, DIMENSIONS, DEFINITIONS)


def render_pdf(report):
    if 'Mulish' not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont('Mulish', str(Path(__file__).resolve().parents[1] / 'assets/fonts/Mulish.ttf')))
    stream = io.BytesIO()
    width = A4[0] - 88
    styles = {
        'body': ParagraphStyle('body', fontName='Helvetica', fontSize=9, leading=12, textColor=colors.HexColor('#' + INK), spaceAfter=5),
        'small': ParagraphStyle('small', fontName='Helvetica', fontSize=8, leading=11, textColor=colors.HexColor('#' + MUTED), spaceAfter=4),
        'title': ParagraphStyle('title', fontName='Helvetica-Bold', fontSize=24, leading=28, textColor=colors.HexColor('#' + INK), spaceAfter=8),
        'h': ParagraphStyle('h', fontName='Helvetica-Bold', fontSize=12, leading=16, textColor=colors.HexColor('#' + INK), spaceBefore=12, spaceAfter=7, keepWithNext=True),
        'value': ParagraphStyle('value', fontName='Helvetica-Bold', fontSize=22, leading=26, textColor=colors.HexColor('#' + INK)),
        'chart': ParagraphStyle('chart', fontName='Mulish', fontSize=9, leading=12, textColor=colors.HexColor('#'+INK)),
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
            maximum = max([max(r[1:]) for r in report['trend']] + [1])
            drawing = Drawing(width, 185)
            left, bottom, plot_width, plot_height = 28, 28, width - 44, 147
            for tick in range(5):
                y = bottom + plot_height * tick / 4
                drawing.add(Line(left, y, left + plot_width, y, strokeColor=colors.HexColor('#E3E3DE'), strokeWidth=.5))
                drawing.add(String(0, y - 3, f'{maximum * tick / 4:.0f}', fontName='Mulish', fontSize=8, fillColor=colors.HexColor('#'+MUTED)))
            for i, (month, received, resolved) in enumerate(rows):
                x = left + plot_width * i / max(1, len(rows)-1)
                if i % 3 == 0 or i == len(rows)-1:
                    drawing.add(String(x - 13, 10, month[2:], fontName='Mulish', fontSize=8, fillColor=colors.HexColor('#'+MUTED)))
                for series_index, count, color in [(1, received, BLUE), (2, resolved, ORANGE)]:
                    y = bottom + count / maximum * plot_height
                    shade = colors.HexColor('#'+color)
                    if i:
                        previous_y = bottom + rows[i-1][series_index] / maximum * plot_height
                        previous_x = left + plot_width * (i-1) / max(1, len(rows)-1)
                        drawing.add(Line(previous_x, previous_y, x, y, strokeColor=shade, strokeWidth=2))
                    drawing.add(Circle(x, y, 2, fillColor=shade, strokeColor=None))
            content += [drawing, p(f'Escala: 0 a {maximum} solicitudes. Mes de registro; no de resolución.', 'small')]
            content.append(table(
                [[p('Mes', 'small'), p('Registradas', 'small'), p('Resueltas actualmente', 'small')]] +
                [[p(month), p(received), p(resolved)] for month, received, resolved in rows],
                [width / 3] * 3,
            ))

        content.append(PageBreak())
        content += [p('Distribución de solicitudes', 'title'), p(f'Total filtrado: {report["total"]:,} solicitudes. Grupos vulnerables indica su base clasificada.', 'small')]
        for key, title in DIMENSIONS:
            content.append(p(title, 'h'))
            total = category_total(report, key)
            if key in DONUT_KEYS and total:
                shown = donut_rows(report['groups'][key])
                chart = Drawing(190, 190)
                angle = 90
                largest = max(range(len(shown)), key=lambda i: shown[i][1]) if shown else -1
                displayed = sum(n for _, n in shown)
                summed = sum(count for _, count in shown)
                for i, (_, count) in enumerate(shown):
                    sweep = count / summed * 360 if summed else 0
                    if sweep:
                        mid = math.radians(angle - sweep/2)
                        shift = 8 if i == largest and len(shown) > 1 else 0
                        chart.add(Wedge(95+shift*math.cos(mid), 95+shift*math.sin(mid), 85, angle-sweep, angle, radius1=55, annular=False, fillColor=colors.HexColor('#'+PALETTE[i]), strokeColor=None))
                    angle -= sweep
                chart.add(String(95, 96, str(displayed), textAnchor='middle', fontName='Mulish', fontSize=24, fillColor=colors.HexColor('#'+INK)))
                chart.add(String(95, 79, 'mostradas', textAnchor='middle', fontName='Mulish', fontSize=11, fillColor=colors.HexColor('#'+MUTED)))
                mode = category_chart_type(report, key)
                if mode != 'donut':
                    chart = Drawing(width, 65 if mode == 'stacked' else 30)
                    chart.add(String(width/2, chart.height-18, f'{displayed:,} solicitudes mostradas', textAnchor='middle', fontName='Mulish', fontSize=16, fillColor=colors.HexColor('#'+INK)))
                    if mode == 'stacked':
                        left = 0
                        for i, (_, count) in enumerate(shown):
                            segment = width * count / displayed
                            chart.add(Rect(left, 15, segment, 20, fillColor=colors.HexColor('#'+PALETTE[i]), strokeColor=None))
                            left += segment
                        chart.add(String(width/2, 0, 'Composición de las categorías mostradas', textAnchor='middle', fontName='Mulish', fontSize=9, fillColor=colors.HexColor('#'+MUTED)))
                if mode == 'treemap':
                    chart = Drawing(width, 220)
                    chart.add(String(width/2, 205, f'{displayed:,} solicitudes mostradas', textAnchor='middle', fontName='Mulish', fontSize=16))
                    for i, x, y, w, h in treemap_rects([n for _, n in shown], width=width, height=190):
                        chart.add(Rect(x, 190-y-h, w, h, fillColor=colors.HexColor('#'+PALETTE[i]), strokeColor=colors.white, strokeWidth=1))
                        label = str(shown[i][1])
                        if w > pdfmetrics.stringWidth(label, 'Mulish', 12) + 6 and h > 18:
                            chart.add(String(x+w/2, 190-y-h/2-4, label, textAnchor='middle', fontName='Mulish', fontSize=12, fillColor=colors.black if i < 2 else colors.white))
                chart.hAlign = 'CENTER'
                heading = content.pop()
                outside = sum(n for _, n in report['groups'][key][5:])
                scope = p(f'Fuera de la gráfica: {outside:,}. Total: {total:,}. Porcentajes sobre el total; áreas sobre las {displayed:,} mostradas.', 'small')
                legend = []
                for i, (name, count) in enumerate(shown):
                    dot = Drawing(10, 12)
                    dot.add(Circle(5, 6, 4, fillColor=colors.HexColor('#'+PALETTE[i]), strokeColor=None))
                    row = [dot, p(name, 'chart')]
                    if mode == 'bars':
                        bar = Drawing(130, 16)
                        maximum = max([value for _, value in shown] + [1])
                        bar.add(Rect(0, 4, 130, 8, fillColor=colors.HexColor('#'+PAPER), strokeColor=None))
                        bar.add(Rect(0, 4, 130*count/maximum, 8, fillColor=colors.HexColor('#'+PALETTE[i]), strokeColor=None))
                        row.append(bar)
                    row.append(p(f'{count:,} · {count / total:.1%}', 'chart'))
                    legend.append(row)
                legend_table = Table(legend, colWidths=([18, width-258, 140, 100] if mode == 'bars' else [18, width-118, 100]))
                legend_table.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP')]))
                content += [KeepTogether([heading, chart, legend_table, scope]), Spacer(1, 10), p(f'Tabla completa. Base: {total:,} solicitudes.', 'small')]
            maximum = max([count for _, count in report['groups'][key]] + [1])
            data = [[p('Categoría', 'small'), p('Solicitudes', 'small'), p('Total / %', 'small')]]
            for name, count in report['groups'][key]:
                bar = Drawing(125, 12)
                bar.add(Rect(0, 2, 125, 7, rx=3.5, fillColor=colors.HexColor('#'+PAPER), strokeColor=None))
                bar.add(Rect(0, 2, count / maximum * 125, 7, rx=3.5, fillColor=colors.HexColor('#' + BLUE), strokeColor=None))
                data.append([p(name), p(count) if key in DONUT_KEYS else bar,
                             p(f'{count:,} / {count / total:.1%}' if total else 'No aplica')])
            content.append(table(data, [width - 240, 140, 100]))
            if key not in DONUT_KEYS:
                content.append(p(f'Escala: 0 a {maximum:,} solicitudes.', 'small'))

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
