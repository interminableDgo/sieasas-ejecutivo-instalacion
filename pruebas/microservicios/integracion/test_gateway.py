"""Integración a través del gateway con los contenedores en ejecución. Solo hace GET.

    $env:GATEWAY_URL = 'http://localhost:8080'
    $env:SGSC_TEST_TOKEN = '<token de sesión emitido manualmente>'   # opcional
    python -m pytest pruebas/microservicios/integracion -q

Sin GATEWAY_URL las pruebas se omiten. Sin SGSC_TEST_TOKEN solo se ejecutan las que no
requieren sesión (la sesión se obtiene iniciando sesión en la app; esta prueba no llama a
/auth/login porque esa ruta escribe en la base de datos).
"""
import os

import pytest

httpx = pytest.importorskip('httpx')
GATEWAY = os.getenv('GATEWAY_URL', '').rstrip('/')
TOKEN = os.getenv('SGSC_TEST_TOKEN', '')
pytestmark = pytest.mark.skipif(not GATEWAY, reason='Define GATEWAY_URL para probar el gateway en ejecución.')
needs_token = pytest.mark.skipif(not TOKEN, reason='Define SGSC_TEST_TOKEN con una sesión válida.')

ROUTES = [
    ('/ejecutivo/dashboard', 'indicadores'),
    ('/ejecutivo/comparacion?inicio=2025-01-01&fin=2025-01-31&inicio=2026-01-01&fin=2026-01-31', 'indicadores'),
    ('/ejecutivo/catalogos', 'indicadores'),
    ('/ejecutivo/solicitudes', 'detalle'),
    ('/ejecutivo/solicitudes/sugerencias?q=a', 'detalle'),
    ('/ejecutivo/solicitudes/2147483647', 'detalle'),
    ('/ejecutivo/personas?tipo=beneficiario&q=zz', 'registro'),
    ('/ejecutivo/colonias?municipio_id=1', 'registro'),
    ('/ejecutivo/municipios-nacimiento?entidad_id=19', 'registro'),
    ('/ejecutivo/exportar/pdf', 'reportes'),
]


@pytest.fixture(scope='module')
def client():
    with httpx.Client(base_url=GATEWAY, timeout=120) as http:
        yield http


@pytest.mark.parametrize('path,service', ROUTES)
def test_without_session_each_service_answers_401(client, path, service):
    response = client.get(path)
    assert response.status_code == 401, response.text
    assert response.headers['x-sgsc-service'] == service


def test_registration_post_reaches_registro_and_requires_session(client):
    response = client.post('/ejecutivo/solicitudes', json={})
    assert response.status_code == 401 and response.headers['x-sgsc-service'] == 'registro'


@pytest.mark.parametrize('path', ['/ejecutivo/desconocida', '/ciudadano/solicitudes', '/docs', '/openapi.json'])
def test_unpublished_paths_are_404(client, path):
    assert client.get(path).status_code == 404


def test_health(client):
    assert client.get('/nginx-health').status_code == 200
    assert client.get('/health').json() == {'status': 'ok'}
    for service in ['indicadores', 'detalle', 'registro', 'reportes']:
        response = client.get(f'/health/{service}')
        assert response.status_code == 200, response.text
        assert response.json()['service'] == service and response.json()['database'] == 'connected'


@needs_token
@pytest.mark.parametrize('path,service', ROUTES)
def test_with_session_each_route_is_served_by_its_service(client, path, service):
    response = client.get(path, headers={'Authorization': 'Bearer ' + TOKEN})
    expected = 404 if path.endswith('/2147483647') else 200
    assert response.status_code == expected, response.text[:300]
    assert response.headers['x-sgsc-service'] == service
    assert response.headers['cache-control'] == 'no-store'


@needs_token
def test_session_is_valid_in_the_core_too(client):
    assert client.get('/auth/me', headers={'Authorization': 'Bearer ' + TOKEN}).status_code == 200
