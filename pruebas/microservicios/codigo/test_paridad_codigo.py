"""Paridad entre el monolito y los microservicios mientras ambos coexisten.

Render sigue desplegando backend/app y Docker despliega los microservicios. Hasta la etapa 8
(consolidación) la lógica del Ejecutivo existe en los dos lugares; estas pruebas fallan si
alguna copia se modifica sin la otra:
- la lógica de negocio copiada es textualmente idéntica;
- cada endpoint del Ejecutivo existe en exactamente un microservicio, con el mismo método,
  código de estado, parámetros, cuerpo y respuestas en OpenAPI.
"""
import inspect
import textwrap
from pathlib import Path

import pytest

from app.main import app as monolito
from app.routers import executive
from app import security
from app.services import executive_service as original
from sgsc_common import auth, consulta
from sgsc_indicadores import routes as r_indicadores, service as indicadores
from sgsc_indicadores.main import app as app_indicadores
from sgsc_detalle import routes as r_detalle, service as detalle
from sgsc_detalle.main import app as app_detalle
from sgsc_registro import routes as r_registro
from sgsc_registro.main import app as app_registro
from sgsc_reportes import routes as r_reportes
from sgsc_reportes.main import app as app_reportes

BACKEND = Path(__file__).resolve().parents[3] / 'backend'
SERVICIOS = {'indicadores': app_indicadores, 'detalle': app_detalle, 'registro': app_registro, 'reportes': app_reportes}


def source(obj):
    return textwrap.dedent(inspect.getsource(obj)).strip()


def text(path):
    return path.read_text(encoding='utf-8').replace('\r\n', '\n')


@pytest.mark.parametrize('name', ['filters', 'where_clause', 'query_rows', 'groups', 'month_series', 'dashboard',
                                  'looks_like_date', 'search_terms', 'folio_number', 'matches'])
def test_common_query_functions_are_identical(name):
    assert source(getattr(consulta, name)) == source(getattr(original, name))


@pytest.mark.parametrize('name', ['JOINS', 'RESOLVED', 'ACTIVE', 'NOT_COMPETENT', 'CANCELLED', 'FILTER_COLUMNS',
                                  'MAX_VALUES_PER_FILTER', 'BENEFICIARY', 'APPLICANT', 'DATES', 'MONTHS', 'MAX_SEARCH_TERMS'])
def test_common_query_constants_are_identical(name):
    assert getattr(consulta, name) == getattr(original, name)


def test_catalogs_are_identical():
    assert consulta.CATALOGS == executive.CATALOGS
    def body(fn):  # sin decoradores ni firma: en el monolito es un endpoint, aquí una función
        lines = [line for line in source(fn).splitlines() if not line.startswith('@')]
        return '\n'.join(lines[1:])
    assert body(consulta.catalogs) == body(executive.catalogs).replace('svc.query_rows', 'query_rows')


@pytest.mark.parametrize('module,names', [
    (indicadores, ['MAX_PERIODS', 'PERIOD_KEYS', 'variation', 'compare_periods']),
    (detalle, ['ROW_SELECT', 'PEOPLE_SELECT', 'PEOPLE_JOIN', 'REQUEST_SEARCH', 'SORT_COLUMNS',
               'search_scope', 'list_rows', 'suggestions']),
])
def test_service_logic_is_identical(module, names):
    for name in names:
        value, expected = getattr(module, name), getattr(original, name)
        assert (source(value) == source(expected)) if callable(value) else (value == expected), name


def test_registration_is_a_literal_copy():
    assert text(BACKEND / 'services/registro/sgsc_registro/registration.py') == text(BACKEND / 'app/services/ssnl_registration.py')


@pytest.mark.parametrize('copy,original_file', [('report.py', 'executive_report.py'), ('xlsx.py', 'executive_xlsx.py'),
                                                ('chart_style.py', 'executive_chart_style.py')])
def test_report_rendering_is_a_literal_copy(copy, original_file):
    expected = text(BACKEND / 'app/services' / original_file).replace(
        'app.services.executive_chart_style', 'sgsc_reportes.chart_style').replace('app.services.executive_xlsx', 'sgsc_reportes.xlsx')
    assert text(BACKEND / 'services/reportes/sgsc_reportes' / copy) == expected


def test_report_font_is_the_same_file():
    assert (BACKEND / 'services/reportes/assets/fonts/Mulish.ttf').read_bytes() == (BACKEND / 'app/assets/fonts/Mulish.ttf').read_bytes()


@pytest.mark.parametrize('name', ['digest', 'now', 'authorized_user', 'current_user'])
def test_session_validation_is_identical(name):
    assert source(getattr(auth, name)) == source(getattr(security, name))


def test_user_rules_are_identical():
    assert auth.USER_SQL == security.USER_SQL


@pytest.mark.parametrize('module,name', [
    (r_indicadores, 'dashboard'), (r_indicadores, 'comparison'),
    (r_detalle, 'requests'), (r_detalle, 'request_suggestions'), (r_detalle, 'detail'),
    (r_registro, 'birth_municipalities'), (r_registro, 'colonies'), (r_registro, 'people'), (r_registro, 'create_request'),
    (r_reportes, 'export'),
])
def test_endpoint_bodies_are_identical(module, name):
    assert source(getattr(module, name)) == source(getattr(executive, name))


def executive_operations(app):
    spec = app.openapi()
    return {(path, method): op for path, ops in spec['paths'].items() if path.startswith('/ejecutivo/')
            for method, op in ops.items()}, spec.get('components', {}).get('schemas', {})


def without_tags(operation):
    return {k: v for k, v in operation.items() if k != 'tags'}


def test_every_executive_endpoint_lives_in_exactly_one_service_with_the_same_contract():
    expected, expected_schemas = executive_operations(monolito)
    owners = {}
    for name, app in SERVICIOS.items():
        operations, schemas = executive_operations(app)
        for key, operation in operations.items():
            assert key not in owners, f'{key} está en {owners[key]} y en {name}'
            owners[key] = name
            assert key in expected, f'{name} publica {key}, que no existe en el monolito'
            assert without_tags(operation) == without_tags(expected[key]), key
            for ref in str(operation).split("'#/components/schemas/")[1:]:
                schema = ref.split("'", 1)[0]
                assert schemas[schema] == expected_schemas[schema], schema
    assert set(owners) == set(expected), set(expected) - set(owners)
    assert owners == {
        ('/ejecutivo/catalogos', 'get'): 'indicadores', ('/ejecutivo/dashboard', 'get'): 'indicadores',
        ('/ejecutivo/comparacion', 'get'): 'indicadores',
        ('/ejecutivo/solicitudes', 'get'): 'detalle', ('/ejecutivo/solicitudes/sugerencias', 'get'): 'detalle',
        ('/ejecutivo/solicitudes/{sid}', 'get'): 'detalle',
        ('/ejecutivo/solicitudes', 'post'): 'registro', ('/ejecutivo/personas', 'get'): 'registro',
        ('/ejecutivo/colonias', 'get'): 'registro', ('/ejecutivo/municipios-nacimiento', 'get'): 'registro',
        ('/ejecutivo/exportar/{format}', 'get'): 'reportes',
    }
