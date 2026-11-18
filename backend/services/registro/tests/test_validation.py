"""Validación y escritura del registro con dobles de base de datos. Casos tomados de
backend/tests/test_ssnl.py, test_sprint1.py (HU5) y test_executive.py."""
import uuid
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from pydantic import ValidationError

from sgsc_registro import registration
from sgsc_registro.registration import Applicant, Beneficiary, NewRequest

BENEFICIARY = dict(nombres='A', apellidos='B', fecha_nacimiento='1990-01-01', genero_id=1,
                   municipio_nacimiento_id=1, municipio_id=1, calle='X', numero='1', colonia_id=1,
                   tiempo_residencia=0, con_quien_vive_id=1, numero_hijos=0, seguridad_social_id=1, grupo_vulnerable_id=1)
APPLICANT = dict(nombres='A', apellidos='B', parentesco_id=1, fecha_nacimiento='1990-01-01', telefono='8112345678')


def test_future_birth_is_rejected():
    with pytest.raises(ValidationError):
        Beneficiary(**{**BENEFICIARY, 'fecha_nacimiento': '2999-01-01'})


@pytest.mark.parametrize('field,value', [('con_quien_vive', 'Familia'), ('codigo_postal', '64000'),
                                         ('profesion', 'Empleado'), ('fuente_ingresos', 'Sueldo'), ('area_estudio', 'Ingeniería')])
def test_free_text_location_and_social_fields_are_rejected(field, value):
    with pytest.raises(ValidationError):
        Beneficiary(**{**BENEFICIARY, field: value})


def test_study_area_required_only_when_studying():
    with pytest.raises(ValidationError):
        Beneficiary(**{**BENEFICIARY, 'estudia': True})
    assert Beneficiary(**{**BENEFICIARY, 'estudia': True, 'area_estudio_id': 2}).area_estudio_id == 2
    assert Beneficiary(**{**BENEFICIARY, 'area_estudio_id': 2}).area_estudio_id is None


def test_applicant_address_is_captured_once():
    assert Applicant(**APPLICANT, mismo_domicilio=True).municipio_id is None
    with pytest.raises(ValidationError):
        Applicant(**APPLICANT)
    with pytest.raises(ValidationError):
        Applicant(**APPLICANT, mismo_domicilio=True, calle='Otra calle')
    assert Applicant(**APPLICANT, calle='X', numero='1', municipio_id=1, colonia_id=3).colonia_id == 3


def test_blank_request_rejected():
    with pytest.raises(ValueError):
        NewRequest(nombres=' ', apellidos='A', municipio_id=1, tipo_apoyo_id=1, dependencia_id=1, descripcion='x',
                   idempotencia=uuid.uuid4())


def request_data():
    return dict(beneficiario_id=21, solicitante_id=22, tipo_apoyo_id=1,
                enviado_por_id=1, canal_id=1, unidad_tratante_id=1,
                descripcion='Solicitud ficticia sprint 1', idempotencia=uuid.uuid4())


@pytest.mark.parametrize('field', ['beneficiario_id', 'solicitante_id', 'descripcion', 'canal_id'])
def test_required_request_fields(field):
    values = request_data()
    values.pop(field)
    with pytest.raises(ValidationError):
        NewRequest(**values)


def test_retry_returns_original_without_writing(monkeypatch):
    original = {'solicitud_id': 9, 'folio': 'Solicitud #9'}
    lookup = Mock(return_value=original)
    monkeypatch.setattr(registration, 'existing_request', lookup)
    db = Mock()
    data = NewRequest(**request_data())
    user = {'usuario_id': 42, 'entidad_id': 19}
    assert registration.create_request(data, user, db) == original
    lookup.assert_called_once_with(db, user, data.idempotencia)
    db.execute.assert_not_called()
    db.commit.assert_not_called()


def test_registration_sets_initial_status_author_and_executive_origin(monkeypatch):
    monkeypatch.setattr(registration, 'existing_request', lambda *a: None)
    monkeypatch.setattr(registration, 'require_catalog', lambda *a: None)
    db = Mock()
    db.execute.side_effect = [Mock(scalar=Mock(return_value=1)),
                              Mock(scalar=Mock(return_value=21)),
                              Mock(scalar=Mock(return_value=22)),
                              SimpleNamespace(lastrowid=9), Mock()]
    result = registration.create_request(NewRequest(**request_data()), {'usuario_id': 42, 'entidad_id': 19}, db)
    assert result == {'solicitud_id': 9, 'folio': 'Solicitud #9'}
    writes = db.execute.call_args_list
    assert "descripcion='Inicio'" in str(writes[0].args[0])
    assert writes[3].args[1]['status'] == 1
    assert writes[3].args[1]['uid'] == writes[4].args[1]['uid'] == 42
    assert 'INSERT INTO ejecutivo_registro' in str(writes[4].args[0]) and writes[4].args[1]['sid'] == 9
    db.commit.assert_called_once()
