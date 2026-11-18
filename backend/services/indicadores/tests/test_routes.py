"""Rutas de Indicadores y Filtros con dobles de base de datos (sin red)."""
from datetime import date
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_indicadores import service as svc
from sgsc_indicadores.main import app


@pytest.fixture
def client():
    db = Mock()
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as http:
        yield http, db
    app.dependency_overrides.clear()


@pytest.fixture
def signed_in(client):
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19}
    return client


@pytest.mark.parametrize('path', ['/ejecutivo/dashboard', '/ejecutivo/catalogos',
                                  '/ejecutivo/comparacion?inicio=2024-01-01&fin=2024-01-31&inicio=2025-01-01&fin=2025-01-31'])
def test_unauthenticated_access_denied(client, path):
    http, db = client
    assert http.get(path).status_code == 401
    db.execute.assert_not_called()


def test_only_its_own_routes_are_served(signed_in):
    http, _ = signed_in
    for path in ['/ejecutivo/solicitudes', '/ejecutivo/exportar/pdf', '/ejecutivo/personas?tipo=beneficiario', '/auth/me']:
        assert http.get(path).status_code == 404
    assert http.get('/health').headers['x-sgsc-service'] == 'indicadores'


def test_dashboard_receives_repeated_filters_and_entity(signed_in, monkeypatch):
    http, _ = signed_in
    summary = Mock(return_value={'total': 0})
    monkeypatch.setattr(svc, 'dashboard', summary)
    query = 'municipio_id=1&municipio_id=2&fecha_inicio=2026-01-01&fecha_fin=2026-01-31'
    response = http.get('/ejecutivo/dashboard?' + query)
    assert response.status_code == 200 and response.json() == {'total': 0}
    assert summary.call_args.args[1] == {'entidad_id': 19}
    assert summary.call_args.args[2] == dict(municipio_id=[1, 2], fecha_inicio=date(2026, 1, 1), fecha_fin=date(2026, 1, 31))


@pytest.mark.parametrize('query', ['region_id=1', 'municipio_id=0', 'fecha_inicio=2026-12-01&fecha_fin=2026-01-01'])
def test_invalid_filters_are_422(signed_in, query):
    http, db = signed_in
    assert http.get('/ejecutivo/dashboard?' + query).status_code == 422
    db.execute.assert_not_called()


def test_comparison_pairs_periods_and_rejects_incomplete_pairs(signed_in, monkeypatch):
    http, _ = signed_in
    compare = Mock(return_value={'periodos': []})
    monkeypatch.setattr(svc, 'compare_periods', compare)
    ok = http.get('/ejecutivo/comparacion', params=[('inicio', '2024-02-01'), ('fin', '2024-02-29'),
                                                   ('inicio', '2025-02-01'), ('fin', '2025-02-28'), ('municipio_id', '3')])
    assert ok.status_code == 200
    assert compare.call_args.args[2] == {'municipio_id': 3}
    assert compare.call_args.args[3] == [(date(2024, 2, 1), date(2024, 2, 29)), (date(2025, 2, 1), date(2025, 2, 28))]
    missing = http.get('/ejecutivo/comparacion', params=[('inicio', '2024-02-01'), ('inicio', '2025-02-01'), ('fin', '2025-02-28')])
    assert missing.status_code == 422


def test_catalogs_are_scoped_to_the_user(signed_in, monkeypatch):
    http, _ = signed_in
    catalogs = Mock(return_value={'municipios': []})
    monkeypatch.setattr(svc, 'catalogs', catalogs)
    assert http.get('/ejecutivo/catalogos').json() == {'municipios': []}
    assert catalogs.call_args.args[0] == {'entidad_id': 19}
