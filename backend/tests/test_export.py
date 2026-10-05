"""HU6 isolated tests: synthetic fixtures only; no live database or credentials."""
import io
import os
import sys
import subprocess
import zipfile
import xml.etree.ElementTree as ET
from datetime import date, datetime, timezone

import pytest
from fastapi.testclient import TestClient
from openpyxl import load_workbook
from sqlalchemy.exc import SQLAlchemyError

from app.main import app
from app.database import get_db
from app.security import current_user
from app.routers import executive
from app.services import executive_service as svc
from app.services.executive_report import build_report, render_pdf, render_xlsx, DIMENSIONS


@pytest.fixture
def summary():
    return {'total': 20, 'activas': 11, 'resueltas': 7,
            **{key: [{'id': 1, 'nombre': 'Categoría de prueba', 'total': 20}] for key, _ in DIMENSIONS},
            'tendencia': [{'mes': '2024-02', 'recibidas': 20, 'resueltas': 7}],
            'nombres': 'PERSONA_NO_EXPORTAR', 'items': [{'folio': 'Solicitud #987654'}]}


def report_for(summary, selected=None):
    return build_report(summary, {'entidad': 'Entidad de prueba'}, selected or {}, {},
                        datetime(2026, 10, 3, 1, 0, tzinfo=timezone.utc))


def cells(book):
    return [c for sheet in book for row in sheet for c in row if c.value is not None]


def indicator(book, label):
    c = next(c for row in book['Resumen'] for c in row if c.value == label)
    return book['Resumen'].cell(c.row + 1, c.column).value


def category_row(book, sheet, label):
    return next(c.row for row in book[sheet] for c in row if c.value == label)


def pdf_text(content, tmp_path):
    python = os.getenv('PDF_TEST_PYTHON', sys.executable)
    if python == sys.executable:
        pytest.importorskip('pypdf', reason='Install pypdf or set PDF_TEST_PYTHON for PDF inspection.')
    source = tmp_path / 'report.pdf'
    source.write_bytes(content)
    result = subprocess.run([python, '-c',
        "import sys; from pypdf import PdfReader; print('\\n'.join(p.extract_text() for p in PdfReader(sys.argv[1]).pages))", str(source)],
        check=True, capture_output=True, env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
    return result.stdout.decode('utf-8')


def test_allowlist_numeric_excel_and_no_individual_rows(summary):
    report = report_for(summary)
    assert 'PERSONA_NO_EXPORTAR' not in repr(report)
    assert 'Solicitud #987654' not in repr(report)
    book = load_workbook(io.BytesIO(render_xlsx(report)))
    assert book.sheetnames == ['Resumen', 'Tendencia', *[title for _, title in DIMENSIONS]]
    assert indicator(book, 'Solicitudes') == 20
    assert indicator(book, 'Otros estatus') == 2
    assert indicator(book, 'Porcentaje resuelto') == .35
    row = category_row(book, 'Tipos de apoyo', 'Categoría de prueba')
    assert book['Tipos de apoyo'].cell(row, 14).data_type == 'n'
    assert book['Tipos de apoyo'].cell(row, 16).value == 1
    assert len(book['Tendencia']._charts) == 1
    assert len(book['Municipios']._charts) == 1
    assert not any('PERSONA_NO_EXPORTAR' in str(c.value) or 'Solicitud #' in str(c.value)
                   for sheet in book for row in sheet for c in row)


def test_pdf_metadata_definitions_and_privacy(summary, tmp_path):
    report = report_for(summary, {'fecha_inicio': date(2024, 2, 1), 'fecha_fin': date(2024, 2, 29)})
    text = pdf_text(render_pdf(report), tmp_path)
    for expected in ['Reporte ejecutivo', '2024-02-01 al 2024-02-29', '2026-10-03 01:00 UTC',
                     'Tendencia mensual', 'Municipios', 'Definiciones', '35.0%', 'cohorte']:
        assert expected in text
    assert 'PERSONA_NO_EXPORTAR' not in text and 'Solicitud #987654' not in text


def test_formula_and_markup_are_literal(summary, tmp_path):
    summary['municipios'][0]['nombre'] = '=HYPERLINK("x") <script> & prueba'
    report = report_for(summary)
    book = load_workbook(io.BytesIO(render_xlsx(report)))
    labels = [c for c in cells(book) if str(c.value).startswith('=HYPERLINK')]
    assert labels and all(c.data_type == 's' for c in labels)
    assert '<script>' in pdf_text(render_pdf(report), tmp_path)


def test_empty_report_no_fake_chart_or_division(summary, tmp_path):
    summary.update(total=0, activas=0, resueltas=0, tendencia=[])
    summary.update({key: [] for key, _ in DIMENSIONS})
    report = report_for(summary)
    assert report['ratio'] is None
    book = load_workbook(io.BytesIO(render_xlsx(report)))
    assert all(not sheet._charts for sheet in book)
    assert 'Sin resultados' in pdf_text(render_pdf(report), tmp_path)


def test_long_labels_all_categories_and_months_are_retained(summary, tmp_path):
    summary.update(total=120, activas=60, resueltas=60)
    summary['municipios'] = [{'nombre': f'Categoría {i:03} con una etiqueta extensa para verificar el ajuste de líneas', 'total': 2} for i in range(60)]
    summary['tendencia'] = [{'mes': f'{2023 + i // 12}-{i % 12 + 1:02}', 'recibidas': 5, 'resueltas': 2} for i in range(24)]
    report = report_for(summary)
    book = load_workbook(io.BytesIO(render_xlsx(report)))
    for row in summary['municipios']:
        assert row['nombre'] in [c.value for c in cells(book)]
    assert len(book['Municipios']._charts) == 1
    assert len(book['Tendencia']._charts) == 1
    text = pdf_text(render_pdf(report), tmp_path)
    assert 'Categoría 059' in text and '2023-01' in text and '2024-12' in text


@pytest.mark.parametrize('selected,expected', [({}, 'Todo el historial'),
    ({'fecha_inicio': date(2024, 1, 1)}, 'Sin límite final'),
    ({'fecha_fin': date(2024, 1, 31)}, 'Sin límite inicial')])
def test_open_periods(summary, selected, expected):
    assert expected in report_for(summary, selected)['period']


@pytest.mark.parametrize('with_end', [True, False])
def test_full_history_scope_and_final_day(monkeypatch, with_end):
    calls = []
    def query(db, sql, params):
        calls.append((sql, params))
        if 'DATE_FORMAT' in sql:
            return [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1},
                    {'mes': '2020-03', 'recibidas': 3, 'resueltas': 0}]
        if 'GROUP BY' in sql:
            return [{'id': 1, 'nombre': 'Prueba', 'total': 5}]
        return [{'total': 5, 'activas': 4, 'resueltas': 1}]
    monkeypatch.setattr(svc, 'query_rows', query)
    selected = {'municipio_id': [3, 4]}
    if with_end:
        selected['fecha_fin'] = date(2020, 3, 31)
    result = svc.dashboard(None, {'entidad_id': 19}, selected, full_history=True)
    assert [r['mes'] for r in result['tendencia']] == ['2020-01', '2020-02', '2020-03']
    assert sum(r['recibidas'] for r in result['tendencia']) == result['total']
    for sql, params in calls:
        assert 'm.entidad_id=:entidad_id' in sql
        expected = {'entidad_id': 19, 'municipio_id_0': 3, 'municipio_id_1': 4}
        if with_end:
            assert 'sa.created<DATE_ADD(:fecha_fin, INTERVAL 1 DAY)' in sql
            expected['fecha_fin'] = date(2020, 3, 31)
        assert params == expected
        assert 'ben_gen_name' not in sql and 'solapoyo_id AS' not in sql


@pytest.fixture
def client(monkeypatch, summary):
    calls = []
    def aggregate(db, user, selected, **kwargs):
        calls.append((user, selected, kwargs))
        return summary
    monkeypatch.setattr(svc, 'dashboard', aggregate)
    monkeypatch.setattr(svc, 'list_rows', lambda *a: pytest.fail('Export must never query individual requests'))
    monkeypatch.setattr(executive, 'catalogs', lambda *a: {'municipios': [{'id': 3, 'nombre': 'Municipio A'}, {'id': 4, 'nombre': 'Municipio B'}]})
    app.dependency_overrides[get_db] = lambda: None
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19, 'entidad': 'Entidad de prueba'}
    with TestClient(app) as client:
        yield client, calls
    app.dependency_overrides.clear()


@pytest.mark.parametrize('format', ['pdf', 'xlsx'])
def test_api_filters_format_scope_and_no_row_limit(client, summary, format):
    client, calls = client
    summary['total'] = 10001
    response = client.get('/ejecutivo/exportar/' + format, params=[('municipio_id', '3'), ('municipio_id', '4'), ('estatus_id', '1'), ('fecha_inicio', '2024-02-01'), ('fecha_fin', '2024-02-29')])
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert response.headers['content-disposition'].endswith(f'.{format}"')
    assert response.content.startswith(b'%PDF' if format == 'pdf' else b'PK')
    assert calls == [({'entidad_id': 19, 'entidad': 'Entidad de prueba'},
                     {'municipio_id': [3, 4], 'estatus_id': 1, 'fecha_inicio': date(2024, 2, 1), 'fecha_fin': date(2024, 2, 29)}, {'full_history': True})]
    if format == 'xlsx':
        book = load_workbook(io.BytesIO(response.content))
        assert any('Municipio A, Municipio B' in str(c.value) for c in cells(book))


@pytest.mark.parametrize('path', ['/ejecutivo/exportar/csv', '/ejecutivo/exportar/pdf?fecha_inicio=2024-03-01&fecha_fin=2024-02-01', '/ejecutivo/exportar/pdf?municipio_id=0'])
def test_api_validation(client, path):
    client, calls = client
    assert client.get(path).status_code == 422
    assert not calls


def test_api_unauthenticated_and_database_failure(client, monkeypatch):
    client, _ = client
    del app.dependency_overrides[current_user]
    assert client.get('/ejecutivo/exportar/pdf').status_code == 401
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19}
    def fail(*args, **kwargs):
        raise SQLAlchemyError('synthetic database failure')
    monkeypatch.setattr(svc, 'dashboard', fail)
    assert client.get('/ejecutivo/exportar/pdf').status_code == 503


def test_many_filter_labels_are_readable(summary, tmp_path):
    labels = [{'id': i, 'nombre': f'Municipio de prueba {i:03} con una descripción extensa'} for i in range(1, 101)]
    report = build_report(summary, {'entidad': 'Prueba'}, {'municipio_id': list(range(1, 101))}, {'municipios': labels})
    book = load_workbook(io.BytesIO(render_xlsx(report)))
    assert all((row.height or 0) <= 409 for row in book['Resumen'].row_dimensions.values())
    assert 'prueba 100' in ' '.join(str(cell.value) for row in book['Resumen'] for cell in row)
    assert 'prueba 100' in pdf_text(render_pdf(report), tmp_path)


def test_download_chart_colors_rankings_and_timezone(summary):
    summary['municipios'] = [{'nombre': f'Municipio {i}', 'total': 1} for i in range(12)]
    payload = render_xlsx(report_for(summary))
    book = load_workbook(io.BytesIO(payload))
    assert any('02/10/2026, 19:00' in str(c.value) for c in cells(book))
    assert any('50.0%' in str(c.value) for c in cells(book))  # 10 / 20, not 10 / 10.
    assert any('Empates:' in str(c.value) for c in cells(book))
    for sheet in book:
        assert sheet.print_area and sheet.print_title_rows
    ns = {'c': 'http://schemas.openxmlformats.org/drawingml/2006/chart',
          'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        charts = [ET.fromstring(archive.read(n)) for n in archive.namelist() if n.startswith('xl/charts/chart') and n.endswith('.xml')]
    line = next(c for c in charts if c.find('.//c:lineChart', ns) is not None)
    assert line.find('.//c:legend/c:legendPos', ns).attrib['val'] == 't'
    assert line.find('.//c:legend/c:overlay', ns).attrib['val'] == '0'
    assert [n.attrib['val'] for n in line.findall('.//c:ser/c:spPr/a:ln/a:solidFill/a:srgbClr', ns)] == ['16A5D8', 'FF8200']
    assert line.findall('.//c:ser/c:spPr/a:ln/a:prstDash', ns)[1].attrib['val'] == 'dash'
    assert all(c.find('.//c:valAx/c:scaling/c:min', ns).attrib['val'] == '0' for c in charts)
    series = book['Municipios']._charts[0].series[0]
    ref = series.val.numRef.f
    from openpyxl.utils.cell import range_boundaries
    left, first, right, last = range_boundaries(ref.split('!')[1])
    assert last-first+1 == 10
    counts = [book['Municipios'].cell(row, left).value for row in range(first, last+1)]
    assert counts == sorted(counts)  # Bottom-to-top source order for horizontal bars.


def test_excel_chart_bounds_leave_space_before_following_content(summary):
    summary['municipios'] = [{'nombre': f'Municipio {i}', 'total': i+1} for i in range(12)]
    book = load_workbook(io.BytesIO(render_xlsx(report_for(summary))))
    for sheet in book:
        for chart in sheet._charts:
            anchor = chart.anchor
            assert anchor._from.col == 1 and anchor.to.col == 17
            assert all(sheet.row_dimensions[r].height == 22
                       for r in range(anchor._from.row+1, anchor.to.row+2))
            below = next(c.row for row in sheet for c in row
                         if c.value == ('Definiciones y alcance' if sheet.title == 'Resumen'
                                        else 'Mes de registro' if sheet.title == 'Tendencia' else 'Categoría'))
            assert below >= anchor.to.row + 3
            assert chart.x_axis.delete is False and chart.y_axis.delete is False
            if chart.tagname == 'barChart':
                assert chart.dLbls.showVal is True
                assert chart.dLbls.showSerName is False
                assert chart.dLbls.showCatName is False
                assert chart.dLbls.showLegendKey is False
    for label in ['Solicitudes', 'Activas', 'Resueltas', 'Otros estatus', 'Porcentaje resuelto']:
        c = next(c for row in book['Resumen'] for c in row if c.value == label)
        assert c.alignment.horizontal == 'center'
        assert book['Resumen'].cell(c.row+1, c.column).alignment.horizontal == 'center'
