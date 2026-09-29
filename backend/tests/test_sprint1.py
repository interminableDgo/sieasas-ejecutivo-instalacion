"""Sprint 1: real routes and rules, with database/mail doubles (no network)."""
from datetime import date
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.database import get_db
from app.main import app
from app.routers import auth, executive
from app.schemas.auth import RegisterInput, ResetInput
from app.security import current_user, verify_password
from app.services import executive_service as svc
from app.services import ssnl_registration as registration


@pytest.fixture
def client():
    db = Mock()
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as http:
        yield http, db
    app.dependency_overrides.clear()
    app.dependency_overrides.update(previous)


@pytest.mark.parametrize('length,accepted', [(14, False), (15, True), (128, True), (129, False)])
def test_hu1_password_policy_matches_registration(length, accepted):
    data = {'token': 't' * 43, 'password': 'a' * length}
    for schema, values in [(ResetInput, data), (RegisterInput, {'correo': 'test@example.com', 'password': data['password']})]:
        if accepted:
            assert schema(**values).password == data['password']
        else:
            with pytest.raises(ValidationError):
                schema(**values)


def test_hu1_forgot_generic_response_and_delivery_scheduled(client, monkeypatch):
    http, _ = client
    monkeypatch.setattr(auth, 'limit_request', lambda *a: None)
    monkeypatch.setattr(auth, 'mail_configured', lambda: True)
    sent = []
    monkeypatch.setattr(auth, 'deliver_reset', sent.append)
    responses = [http.post('/auth/forgot-password', json={'correo': address}) for address in ['known@example.com', 'unknown@example.com']]
    assert [r.status_code for r in responses] == [202, 202]
    assert responses[0].json() == responses[1].json() == auth.GENERIC
    assert sent == ['known@example.com', 'unknown@example.com']


def test_hu1_reset_invalid_credential_does_not_write(client, monkeypatch):
    http, db = client
    monkeypatch.setattr(auth, 'lock_token', lambda *a: None)
    response = http.post('/auth/reset-password', json={'token': 'x' * 43, 'password': 'Una nueva frase segura 2026'})
    assert response.status_code == 400
    db.execute.assert_not_called()
    db.commit.assert_not_called()


def test_hu1_reset_hashes_password_and_requests_session_revocation(client, monkeypatch):
    http, db = client
    monkeypatch.setattr(auth, 'lock_token', lambda *a: {'usuario_id': 42})
    monkeypatch.setattr(auth, 'authorized_user', lambda *a: {'usuario_id': 42})
    secret = 'Una nueva frase segura 2026'
    response = http.post('/auth/reset-password', json={'token': 'x' * 43, 'password': secret})
    assert response.status_code == 200
    calls = db.execute.call_args_list
    assert len(calls) == 2
    assert verify_password(calls[0].args[1]['hash'], secret)
    assert calls[0].args[1]['hash'] != secret
    assert calls[0].args[1]['uid'] == calls[1].args[1]['uid'] == 42
    assert 'usado IS NULL' in str(calls[1].args[0])
    db.commit.assert_called_once()


def request_data():
    return dict(beneficiario_id=21, solicitante_id=22, tipo_apoyo_id=1,
                enviado_por_id=1, canal_id=1, unidad_tratante_id=1,
                descripcion='Solicitud ficticia sprint 1', idempotencia=uuid4())


@pytest.mark.parametrize('field', ['beneficiario_id', 'solicitante_id', 'descripcion', 'canal_id'])
def test_hu5_required_request_fields(field):
    values = request_data()
    values.pop(field)
    with pytest.raises(ValidationError):
        registration.NewRequest(**values)


def test_hu5_retry_returns_original_without_writing(monkeypatch):
    original = {'solicitud_id': 9, 'folio': 'Solicitud #9'}
    lookup = Mock(return_value=original)
    monkeypatch.setattr(registration, 'existing_request', lookup)
    db = Mock()
    data = registration.NewRequest(**request_data())
    user = {'usuario_id': 42, 'entidad_id': 19}
    assert registration.create_request(data, user, db) == original
    lookup.assert_called_once_with(db, user, data.idempotencia)
    db.execute.assert_not_called()
    db.commit.assert_not_called()


def test_hu5_registration_sets_initial_status_and_author(monkeypatch):
    monkeypatch.setattr(registration, 'existing_request', lambda *a: None)
    monkeypatch.setattr(registration, 'require_catalog', lambda *a: None)
    db = Mock()
    db.execute.side_effect = [Mock(scalar=Mock(return_value=1)),
                             Mock(scalar=Mock(return_value=21)),
                             Mock(scalar=Mock(return_value=22)),
                             SimpleNamespace(lastrowid=9), Mock()]
    result = registration.create_request(registration.NewRequest(**request_data()), {'usuario_id': 42, 'entidad_id': 19}, db)
    assert result == {'solicitud_id': 9, 'folio': 'Solicitud #9'}
    writes = db.execute.call_args_list
    assert "descripcion='Inicio'" in str(writes[0].args[0])
    assert writes[3].args[1]['status'] == 1
    assert writes[3].args[1]['uid'] == writes[4].args[1]['uid'] == 42
    assert writes[4].args[1]['sid'] == 9
    db.commit.assert_called_once()


@pytest.mark.parametrize('path,method', [('/ejecutivo/solicitudes', 'post'), ('/ejecutivo/dashboard', 'get'), ('/ejecutivo/solicitudes/9', 'get')])
def test_hu4_hu5_unauthenticated_access_denied(client, path, method):
    http, db = client
    assert getattr(http, method)(path).status_code == 401
    db.execute.assert_not_called()


def test_hu4_detail_query_keeps_entity_scope(client, monkeypatch):
    http, _ = client
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19}
    calls = []
    def query(db, sql, params):
        calls.append((sql, params))
        return []
    monkeypatch.setattr(svc, 'query_rows', query)
    assert http.get('/ejecutivo/solicitudes/9').status_code == 404
    assert calls[0][1] == {'entidad_id': 19, 'sid': 9}
    assert 'm.entidad_id=:entidad_id' in calls[0][0]


def test_hu3_dashboard_and_list_receive_same_filters(client, monkeypatch):
    http, _ = client
    app.dependency_overrides[current_user] = lambda: {'entidad_id': 19}
    summary = Mock(return_value={'total': 0})
    rows = Mock(return_value={'total': 0, 'items': []})
    monkeypatch.setattr(svc, 'dashboard', summary)
    monkeypatch.setattr(svc, 'list_rows', rows)
    query = 'municipio_id=1&municipio_id=2&fecha_inicio=2026-01-01&fecha_fin=2026-01-31'
    assert http.get('/ejecutivo/dashboard?' + query).status_code == 200
    assert http.get('/ejecutivo/solicitudes?' + query).status_code == 200
    expected = dict(municipio_id=[1, 2], fecha_inicio=date(2026, 1, 1), fecha_fin=date(2026, 1, 31))
    assert summary.call_args.args[2] == rows.call_args.args[2] == expected


def test_hu3_inclusive_end_date_and_invalid_period():
    selected = dict(fecha_inicio=date(2026, 1, 1), fecha_fin=date(2026, 1, 31))
    clause, params = svc.where_clause({'entidad_id': 19}, selected)
    assert 'sa.created>=:fecha_inicio' in clause
    assert 'sa.created<DATE_ADD(:fecha_fin, INTERVAL 1 DAY)' in clause
    assert params == {'entidad_id': 19, **selected}
    with pytest.raises(HTTPException) as caught:
        svc.filters(fecha_inicio=date(2026, 2, 1), fecha_fin=date(2026, 1, 1))
    assert caught.value.status_code == 422


def test_hu3_historical_period_keeps_trend_data(monkeypatch):
    """Acceptance check: a historical filter must not lose its trend records."""
    replies = iter([
        [{'total': 2, 'activas': 1, 'resueltas': 1}],
        [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1}],
        [{'id': 1, 'nombre': 'Municipio ficticio', 'total': 2}],
        [{'id': 1, 'nombre': 'Apoyo ficticio', 'total': 2}],
        [{'id': 1, 'nombre': 'Remitente ficticio', 'total': 2}],
        [{'id': 1, 'nombre': 'Grupo ficticio', 'total': 2}],
    ])
    monkeypatch.setattr(svc, 'query_rows', lambda *a: next(replies))
    result = svc.dashboard(None, {'entidad_id': 19}, {
        'fecha_inicio': date(2020, 1, 1), 'fecha_fin': date(2020, 1, 31),
    })
    assert result['total'] == 2
    assert sum(r['recibidas'] for r in result['tendencia']) == 2, (
        'El total contiene 2 solicitudes de enero de 2020, pero la tendencia '
        'las descarta al limitarse a los últimos 12 meses respecto a hoy.'
    )
    assert result['tendencia'] == [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1}]


@pytest.mark.parametrize('start,end,months', [
    (date(2019, 12, 15), date(2020, 2, 5), ['2019-12', '2020-01', '2020-02']),
    (date(2020, 1, 1), date(2021, 1, 31), [f'2020-{m:02d}' for m in range(1, 13)] + ['2021-01']),
    (None, date(2020, 3, 31), ['2020-01', '2020-02', '2020-03']),
    (date(2020, 1, 1), None, ['2020-01', '2020-02', '2020-03']),
])
def test_hu3_trend_period_bounds_and_zero_fill(start, end, months):
    rows = [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1}]
    result = svc.month_series(rows, today=date(2020, 3, 15), start_date=start, end_date=end)
    assert [r['mes'] for r in result] == months
    assert sum(r['recibidas'] for r in result) == 2
    assert sum(r['resueltas'] for r in result) == 1
    assert all(r['recibidas'] == r['resueltas'] == 0 for r in result if r['mes'] != '2020-01')


@pytest.mark.parametrize('start,end,first,last,count', [
    (date(2020, 1, 1), date(2020, 2, 29), '2020-01', '2020-02', 2),
    (None, date(2020, 2, 29), '2019-03', '2020-02', 12),
    (date(2027, 1, 1), None, '2027-01', '2027-01', 1),
])
def test_hu3_empty_filtered_period(start, end, first, last, count):
    result = svc.month_series([], today=date(2026, 9, 28), start_date=start, end_date=end)
    assert (result[0]['mes'], result[-1]['mes'], len(result)) == (first, last, count)
    assert all(r['recibidas'] == r['resueltas'] == 0 for r in result)
