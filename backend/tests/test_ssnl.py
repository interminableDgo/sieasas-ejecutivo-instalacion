import bcrypt
from app.security import verify_password
from app.services.ssnl_registration import Applicant, Beneficiary
from pydantic import ValidationError
import pytest


def test_yii_bcrypt_and_current_argon2_compatibility():
    secret='Una contraseña compatible con SSNL'
    encoded=bcrypt.hashpw(secret.encode(),bcrypt.gensalt()).decode().replace('$2b$','$2y$',1)
    assert verify_password(encoded,secret)
    assert not verify_password(encoded,'incorrecta')
    assert not verify_password('hash-invalido',secret)


BENEFICIARY=dict(nombres='A',apellidos='B',fecha_nacimiento='1990-01-01',genero_id=1,
  municipio_nacimiento_id=1,municipio_id=1,calle='X',numero='1',colonia_id=1,
  tiempo_residencia=0,con_quien_vive_id=1,numero_hijos=0,seguridad_social_id=1,grupo_vulnerable_id=1)
APPLICANT=dict(nombres='A',apellidos='B',parentesco_id=1,fecha_nacimiento='1990-01-01',telefono='8112345678')


def test_future_birth_is_rejected():
    with pytest.raises(ValidationError):
        Beneficiary(**{**BENEFICIARY,'fecha_nacimiento':'2999-01-01'})


@pytest.mark.parametrize('field,value',[('con_quien_vive','Familia'),('codigo_postal','64000'),
    ('profesion','Empleado'),('fuente_ingresos','Sueldo'),('area_estudio','Ingeniería')])
def test_free_text_location_and_social_fields_are_rejected(field,value):
    # Solo se aceptan claves de catálogo; el código postal se deriva de la colonia.
    with pytest.raises(ValidationError):
        Beneficiary(**{**BENEFICIARY,field:value})


def test_study_area_required_only_when_studying():
    with pytest.raises(ValidationError):
        Beneficiary(**{**BENEFICIARY,'estudia':True})
    assert Beneficiary(**{**BENEFICIARY,'estudia':True,'area_estudio_id':2}).area_estudio_id==2
    assert Beneficiary(**{**BENEFICIARY,'area_estudio_id':2}).area_estudio_id is None


def test_applicant_address_is_captured_once():
    assert Applicant(**APPLICANT,mismo_domicilio=True).municipio_id is None
    with pytest.raises(ValidationError):
        Applicant(**APPLICANT)
    with pytest.raises(ValidationError):
        Applicant(**APPLICANT,mismo_domicilio=True,calle='Otra calle')
    with pytest.raises(ValidationError):
        Applicant(**APPLICANT,calle='X',numero='1',municipio_id=1,colonia='Centro')
    assert Applicant(**APPLICANT,calle='X',numero='1',municipio_id=1,colonia_id=3).colonia_id==3
