"""Rutas de Detalle de Indicadores con dobles de base de datos (sin red).
Casos tomados de backend/tests/test_sprint1.py (HU3 y HU4)."""
from datetime import date
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_detalle import service as svc
from sgsc_detalle.main import app


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


@pytest.mark.parametrize('path', ['/ejecutivo/solicitudes', '/ejecutivo/solicitudes/9',
                                  '/ejecutivo/solicitudes/sugerencias?q=ana'])
def test_unauthenticated_access_denied(client, path):
    http, db = client
    assert http.get(path).status_code == 401
    db.execute.assert_not_called()


def test_registration_is_not_served_here(signed_in):
    http, _ = signed_in
    # POST /ejecutivo/solicitudes pertenece a Registro; el gateway lo enruta por método.
    assert http.post('/ejecutivo/solicitudes', json={}).status_code == 405
    assert http.get('/ejecutivo/dashboard').status_code == 404


def test_detail_query_keeps_entity_scope(signed_in, monkeypatch):
    http, _ = signed_in
    calls = []

    def query(db, sql, params):
        calls.append((sql, params))
        return []
    monkeypatch.setattr(svc, 'query_rows', query)
    assert http.get('/ejecutivo/solicitudes/9').status_code == 404
    assert calls[0][1] == {'entidad_id': 19, 'sid': 9}
    assert 'm.entidad_id=:entidad_id' in calls[0][0]


def test_detail_returns_the_row(signed_in, monkeypatch):
    http, _ = signed_in
    monkeypatch.setattr(svc, 'query_rows', lambda *a: [{'solicitud_id': 9, 'folio': 'Solicitud #9'}])
    assert http.get('/ejecutivo/solicitudes/9').json() == {'solicitud_id': 9, 'folio': 'Solicitud #9'}
    assert http.get('/ejecutivo/solicitudes/abc').status_code == 422


def test_list_keeps_the_dashboard_filters_page_and_order(signed_in, monkeypatch):
    http, _ = signed_in
    rows = Mock(return_value={'total': 0, 'items': []})
    monkeypatch.setattr(svc, 'list_rows', rows)
    query = 'municipio_id=1&municipio_id=2&fecha_inicio=2026-01-01&fecha_fin=2026-01-31&page=2&orden=estatus&direccion=asc&q=ana'
    assert http.get('/ejecutivo/solicitudes?' + query).json() == {'total': 0, 'items': []}
    db, user, selected, limit, offset, q, orden, ascending = rows.call_args.args
    assert user == {'entidad_id': 19}
    assert selected == dict(municipio_id=[1, 2], fecha_inicio=date(2026, 1, 1), fecha_fin=date(2026, 1, 31))
    assert (limit, offset, q, orden, ascending) == (10, 20, 'ana', 'estatus', True)


@pytest.mark.parametrize('query', ['orden=sa.created;%20DROP', 'direccion=up', 'page=-1', 'region_id=1'])
def test_invalid_list_parameters_are_422(signed_in, query):
    http, db = signed_in
    assert http.get('/ejecutivo/solicitudes?' + query).status_code == 422
    db.execute.assert_not_called()


def test_suggestions_require_text_and_keep_filters(signed_in, monkeypatch):
    http, _ = signed_in
    hints = Mock(return_value={'total': 0, 'solicitudes': [], 'personas': []})
    monkeypatch.setattr(svc, 'suggestions', hints)
    assert http.get('/ejecutivo/solicitudes/sugerencias').status_code == 422
    assert http.get('/ejecutivo/solicitudes/sugerencias?q=ana&estatus_id=1').status_code == 200
    assert hints.call_args.args[2:] == ({'estatus_id': 1}, 'ana')
