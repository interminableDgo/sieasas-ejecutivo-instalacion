"""Reportes calcula sus agregados sin depender de Indicadores."""
from unittest.mock import Mock

from fastapi.testclient import TestClient

from sgsc_common import consulta
from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_reportes.main import app


def test_export_only_uses_the_common_query_contract(monkeypatch):
    calls = []

    def query(db, sql, params):
        calls.append(sql)
        if 'DATE_FORMAT' in sql:
            return [{'mes': '2026-01', 'recibidas': 3, 'resueltas': 1}]
        if 'GROUP BY' in sql:
            return [{'id': 1, 'nombre': 'Prueba', 'total': 3}]
        if 'COUNT(*) AS total' in sql:
            return [{'total': 3, 'activas': 2, 'resueltas': 1, 'no_competencia': 0, 'canceladas': 0}]
        return []
    # Sin servidor de Indicadores: toda la información sale de consultas de agregados propias.
    monkeypatch.setattr(consulta, 'query_rows', query)
    app.dependency_overrides[get_db] = lambda: Mock()
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19, 'entidad': 'Entidad de prueba'}
    try:
        response = TestClient(app).get('/ejecutivo/exportar/xlsx')
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200 and response.content.startswith(b'PK')
    assert response.headers['x-sgsc-service'] == 'reportes'
    assert calls and all('ben_gen_name' not in sql and 'solapoyo_descripcion' not in sql for sql in calls)


def test_only_its_own_routes_are_served():
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19}
    try:
        client = TestClient(app)
        for path in ['/ejecutivo/dashboard', '/ejecutivo/solicitudes', '/auth/me']:
            assert client.get(path).status_code == 404
    finally:
        app.dependency_overrides.clear()
