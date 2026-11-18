"""Paridad de respuestas: el monolito (iniciar.ps1, puerto 8000) y el gateway (puerto 8080)
deben devolver exactamente el mismo JSON para las mismas consultas. Solo hace GET.

    $env:MONOLITO_URL = 'http://127.0.0.1:8000'
    $env:GATEWAY_URL = 'http://localhost:8080'
    $env:SGSC_TEST_TOKEN = '<token de sesión emitido manualmente>'
    python -m pytest pruebas/microservicios/integracion/test_paridad.py -q

Ambos despliegues usan la misma base de Aiven y validan el mismo token.
"""
import io
import os

import pytest

httpx = pytest.importorskip('httpx')
MONOLITO = os.getenv('MONOLITO_URL', '').rstrip('/')
GATEWAY = os.getenv('GATEWAY_URL', '').rstrip('/')
TOKEN = os.getenv('SGSC_TEST_TOKEN', '')
pytestmark = pytest.mark.skipif(not (MONOLITO and GATEWAY and TOKEN),
                                reason='Define MONOLITO_URL, GATEWAY_URL y SGSC_TEST_TOKEN.')

QUERIES = [
    '/ejecutivo/dashboard',
    '/ejecutivo/dashboard?fecha_inicio=2025-01-01&fecha_fin=2025-12-31',
    '/ejecutivo/comparacion?inicio=2025-01-01&fin=2025-06-30&inicio=2025-07-01&fin=2025-12-31',
    '/ejecutivo/catalogos',
    '/ejecutivo/solicitudes',
    '/ejecutivo/solicitudes?page=1&orden=estatus&direccion=asc',
    '/ejecutivo/solicitudes?q=a',
    '/ejecutivo/solicitudes/sugerencias?q=a',
    '/ejecutivo/personas?tipo=beneficiario&q=a',
    '/ejecutivo/personas?tipo=solicitante&q=a',
    '/ejecutivo/municipios-nacimiento?entidad_id=19',
    '/ejecutivo/dashboard?region_id=1',
    '/ejecutivo/solicitudes/abc',
    '/ejecutivo/exportar/csv',
]


def get(base, path):
    return httpx.get(base + path, headers={'Authorization': 'Bearer ' + TOKEN}, timeout=120)


@pytest.mark.parametrize('path', QUERIES)
def test_same_status_and_json(path):
    before, after = get(MONOLITO, path), get(GATEWAY, path)
    assert after.status_code == before.status_code, path
    assert after.json() == before.json(), path


def test_same_detail_for_the_first_listed_request():
    items = get(MONOLITO, '/ejecutivo/solicitudes').json()['items']
    if not items:
        pytest.skip('No hay solicitudes en la entidad de la cuenta de prueba.')
    path = f"/ejecutivo/solicitudes/{items[0]['solicitud_id']}"
    assert get(GATEWAY, path).json() == get(MONOLITO, path).json()


def test_same_excel_cells():
    from openpyxl import load_workbook
    books = [load_workbook(io.BytesIO(get(base, '/ejecutivo/exportar/xlsx').content)) for base in (MONOLITO, GATEWAY)]
    values = [[[c.value for row in sheet for c in row if c.value is not None]
               for sheet in book if sheet.title != 'Resumen'] for book in books]
    # Resumen incluye la hora de generación; el resto de las hojas debe coincidir celda por celda.
    assert books[0].sheetnames == books[1].sheetnames
    assert values[0] == values[1]
