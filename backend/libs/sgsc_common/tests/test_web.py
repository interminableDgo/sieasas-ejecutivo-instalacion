"""Comportamiento transversal de cada microservicio, igual al de app/main.py."""
from unittest.mock import Mock

from fastapi.testclient import TestClient
from sqlalchemy.exc import SQLAlchemyError

from sgsc_common.database import get_db
from sgsc_common.web import create_app


def make_app():
    app = create_app('prueba', 'Prueba', 'Servicio de prueba')

    @app.get('/falla')
    def failing():
        raise SQLAlchemyError('falla sintética')

    return app


def test_security_headers_and_service_name():
    response = TestClient(make_app()).get('/health')
    assert response.status_code == 200
    assert response.json() == {'status': 'ok', 'service': 'prueba'}
    assert response.headers['cache-control'] == 'no-store'
    assert response.headers['referrer-policy'] == 'no-referrer'
    assert response.headers['x-content-type-options'] == 'nosniff'
    assert response.headers['x-sgsc-service'] == 'prueba'


def test_database_failures_are_503_with_the_same_message():
    response = TestClient(make_app()).get('/falla')
    assert response.status_code == 503
    assert response.json() == {'detail': 'No se pudo consultar la base de datos. Intenta nuevamente.'}


def test_health_db_reports_the_connection():
    app = make_app()
    db = Mock()
    app.dependency_overrides[get_db] = lambda: db
    assert TestClient(app).get('/health/db').json()['database'] == 'connected'
    db.execute.side_effect = RuntimeError('sin conexión')
    assert TestClient(app).get('/health/db').status_code == 503


def test_docs_are_disabled_by_default(monkeypatch):
    monkeypatch.delenv('SGSC_DOCS', raising=False)
    client = TestClient(make_app())
    for path in ['/docs', '/redoc', '/openapi.json']:
        assert client.get(path).status_code == 404


def test_cors_allows_only_configured_origins(monkeypatch):
    monkeypatch.setenv('CORS_ORIGINS', 'http://localhost:8080')
    client = TestClient(make_app())
    preflight = {'Access-Control-Request-Method': 'GET', 'Access-Control-Request-Headers': 'authorization'}
    allowed = client.options('/health', headers={'Origin': 'http://localhost:8080', **preflight})
    assert allowed.headers['access-control-allow-origin'] == 'http://localhost:8080'
    # El patrón *.netlify.app pertenece al prototipo Ciudadano y no se habilita aquí.
    denied = client.options('/health', headers={'Origin': 'https://demo.netlify.app', **preflight})
    assert 'access-control-allow-origin' not in denied.headers
