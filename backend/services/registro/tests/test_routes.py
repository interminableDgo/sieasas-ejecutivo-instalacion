"""Rutas del Registro Ejecutivo con dobles de base de datos (sin red)."""
import uuid
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

from sgsc_common import consulta
from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_registro import routes
from sgsc_registro.main import app

USER = {'usuario_id': 42, 'entidad_id': 19}


@pytest.fixture
def client():
    db = Mock()
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as http:
        yield http, db
    app.dependency_overrides.clear()


@pytest.fixture
def signed_in(client):
    app.dependency_overrides[current_user] = lambda: USER
    return client


@pytest.mark.parametrize('path,method', [('/ejecutivo/solicitudes', 'post'), ('/ejecutivo/personas?tipo=beneficiario', 'get'),
                                         ('/ejecutivo/colonias?municipio_id=1', 'get'),
                                         ('/ejecutivo/municipios-nacimiento?entidad_id=19', 'get')])
def test_unauthenticated_access_denied(client, path, method):
    http, db = client
    assert getattr(http, method)(path).status_code == 401
    db.execute.assert_not_called()


def test_only_its_own_routes_are_served(signed_in):
    http, _ = signed_in
    # GET /ejecutivo/solicitudes pertenece a Detalle; el gateway lo enruta por método.
    assert http.get('/ejecutivo/solicitudes').status_code == 405
    assert http.get('/ejecutivo/dashboard').status_code == 404


def test_post_registers_with_the_authenticated_user(signed_in, monkeypatch):
    http, db = signed_in
    save = Mock(return_value={'solicitud_id': 9, 'folio': 'Solicitud #9'})
    monkeypatch.setattr(routes, 'save_ssnl_request', save)
    body = dict(beneficiario_id=21, solicitante_id=22, tipo_apoyo_id=1, enviado_por_id=1, canal_id=1,
                unidad_tratante_id=1, descripcion='Solicitud ficticia', idempotencia=str(uuid.uuid4()))
    response = http.post('/ejecutivo/solicitudes', json=body)
    assert response.status_code == 201 and response.json() == {'solicitud_id': 9, 'folio': 'Solicitud #9'}
    data, user, session = save.call_args.args
    assert str(data.idempotencia) == body['idempotencia'] and user == USER and session is db


def test_invalid_body_is_422_without_writing(signed_in):
    http, db = signed_in
    assert http.post('/ejecutivo/solicitudes', json={'descripcion': 'x'}).status_code == 422
    assert http.post('/ejecutivo/solicitudes', json={'extra': 1}).status_code == 422
    db.execute.assert_not_called()


def test_people_search_is_scoped_to_the_entity(signed_in, monkeypatch):
    http, _ = signed_in
    calls = []
    monkeypatch.setattr(consulta, 'query_rows', lambda db, sql, params: calls.append((sql, params)) or [])
    assert http.get('/ejecutivo/personas', params={'tipo': 'beneficiario', 'q': 'maria martinez'}).json() == {'items': []}
    assert http.get('/ejecutivo/personas', params={'tipo': 'solicitante', 'q': '8112345678'}).json() == {'items': []}
    (beneficiary_sql, beneficiary), (applicant_sql, applicant) = calls
    assert 'b.ben_dom_entidad=:eid' in beneficiary_sql and beneficiary['eid'] == 19
    assert beneficiary['p0'] == '%maria%' and beneficiary['p1'] == '%martinez%'
    assert 's.sol_estadoid=:eid' in applicant_sql and applicant['exact'] == '8112345678'
    assert http.get('/ejecutivo/personas', params={'tipo': 'otro'}).status_code == 422


def test_colonies_only_from_the_authorized_entity(signed_in, monkeypatch):
    http, _ = signed_in
    calls = []
    monkeypatch.setattr(consulta, 'query_rows', lambda db, sql, params: calls.append((sql, params)) or [])
    http.get('/ejecutivo/colonias', params={'municipio_id': 7})
    assert calls[0][1] == {'mid': 7, 'eid': 19} and 'c.is_active=1' in calls[0][0]
    assert http.get('/ejecutivo/colonias', params={'municipio_id': 0}).status_code == 422
