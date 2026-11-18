import os
import random
import uuid
from datetime import date, datetime

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import engine, get_db
from app.main import app
from app.services import ciudadano_service as svc


def test_curp_gives_birth_sex_and_state():
    assert svc.datos_curp('ROGM900101MNLDRR05') == (date(1990, 1, 1), 'M', '19')
    assert svc.datos_curp('ROLJ580315HNLDPS09') == (date(1958, 3, 15), 'H', '19')
    # Un dígito en la posición 17 indica siglo XX; una letra, siglo XXI.
    assert svc.datos_curp('GODE101231HDFRRNA0')[0] == date(2010, 12, 31)
    assert svc.datos_curp('GODE561231HNERRN00')[2] == ''
    with pytest.raises(HTTPException):
        svc.datos_curp('GODE561331HDFRRN00')


def test_age_counts_birthday():
    assert svc.edad(date(1958, 3, 15), hoy=date(2026, 3, 14)) == 67
    assert svc.edad(date(1958, 3, 15), hoy=date(2026, 3, 15)) == 68


@pytest.mark.parametrize('relacion,sexo,esperado', [
    ('Papá', 'M', ('Hijo / Hija', None)),
    ('mi madre', 'H', ('Hijo / Hija', None)),
    ('Hijo', 'M', ('Madre', None)),
    ('hija', 'H', ('Padre', None)),
    ('Tía', 'H', ('Sobrino / Sobrina', None)),
    ('Esposa', 'H', ('Esposo / Esposa', None)),
    ('Vecino', 'M', ('Vecino / Vecina', None)),
    ('Abuela', 'M', ('Otro', 'Beneficiario: Abuela')),
])
def test_relation_is_inverted_to_the_applicant(relacion, sexo, esperado):
    assert svc.parentesco(relacion, sexo) == esperado


def test_single_vulnerable_group_and_status_mapping():
    assert svc.grupo_vulnerable(['Mujer embarazada', 'Adulto mayor']) == 'Sí, Adulto Mayor'
    assert svc.grupo_vulnerable(['Ninguno']) == 'No'
    assert svc.estatus_app('Inicio')[0] == 'recibida'
    assert svc.estatus_app('En proceso(Pendiente)')[0] == 'enRevision'
    assert svc.estatus_app('Resuelto con observación')[0] == 'atendidaConObservaciones'
    assert svc.estatus_app('Resuelto')[0] == 'atendida'
    assert svc.estatus_app('Cerrado / Cancelado')[0] == 'cancelada'
    assert svc.estatus_app('No es competencia')[0] == 'noEsCompetencia'


def test_dates_are_returned_in_nuevo_leon_time():
    assert svc.fecha_local(datetime(2026, 11, 14, 3, 0)) == '2026-11-13T21:00:00'


def test_profile_rejects_invalid_curp():
    with pytest.raises(ValueError):
        svc.Perfil(curp='NO-ES-CURP')
    assert svc.Perfil(curp='rogm900101mnldrr05').curp == 'ROGM900101MNLDRR05'


PERFIL = {'nombres': 'Persona', 'primerApellido': 'De Prueba', 'segundoApellido': 'Temporal',
          'curp': 'ROGM900101MNLDRR05', 'celular': '81 1234 5678', 'correo': '', 'mediosContacto': ['WhatsApp'],
          'municipio': {'cvegeo': '19039', 'nombre': 'Monterrey'}, 'codigoPostal': '64000', 'colonia': 'Centro',
          'calle': 'Calle Juárez', 'numero': '123', 'aceptaPrivacidad': True, 'confirmaVeracidad': True}


def curp_nueva():
    # CURP con formato válido que no existe en SSNL, para probar el alta del beneficiario.
    letras = ''.join(random.choice('BCDFGHJKLMNPQRSTVWXZ') for _ in range(3))
    return f'R{random.choice("AEIOU")}{letras[:2]}580315HNL{letras}0{random.randint(0, 9)}'


def solicitud(**cambios):
    base = {'folio': 'pendiente', 'asunto': 'Solicitud de andadera', 'tipoApoyo': 'Andadera o bastón',
            'descripcion': 'Para caminar con apoyo.', 'fechaRegistro': '2026-11-13T10:00:00.000',
            'fechaRequerida': '2026-12-01T00:00:00.000', 'riesgoInmediato': False, 'estatus': 'recibida',
            'beneficiario': {'esTitular': False, 'nombres': 'José', 'primerApellido': 'Rodríguez',
                             'segundoApellido': 'López', 'relacion': 'Papá', 'curp': 'ROLJ580315HNLDPS09'},
            'ubicacion': {'usaDomicilioRegistrado': True, 'municipio': {'cvegeo': '19039', 'nombre': 'Monterrey'},
                          'codigoPostal': '64000', 'colonia': 'Centro', 'calle': 'Calle Juárez', 'numero': '123',
                          'referencias': ''},
            'salud': {'seguridadSocial': 'IMSS', 'tarjetaCuidarTuSalud': False, 'unidadMedica': '',
                      'gruposVulnerables': ['Adulto mayor']},
            'adjuntos': [{'nombre': 'receta.pdf', 'tamanoBytes': 1200}], 'historial': [],
            'usaContactoCuenta': True, 'celularContacto': '', 'correoContacto': ''}
    base.update(cambios)
    return base


@pytest.fixture
def live():
    if os.getenv('RUN_DB_TESTS') != '1':
        pytest.skip('Set RUN_DB_TESTS=1 to run transaction-isolated MySQL tests.')
    connection = engine.connect()
    transaction = connection.begin()
    db = Session(bind=connection, join_transaction_mode='create_savepoint')

    def override():
        yield db
    app.dependency_overrides[get_db] = override
    with TestClient(app) as client:
        try:
            yield client, db
        finally:
            app.dependency_overrides.clear()
            db.close()
            transaction.rollback()
            connection.close()


def cuenta(client):
    correo = f'ciudadano-{uuid.uuid4().hex}@example.com'
    r = client.post('/ciudadano/registro', json={'correo': correo, 'contrasena': 'Una frase de prueba 2026'})
    assert r.status_code == 201, r.text
    return correo, {'Authorization': 'Bearer ' + r.json()['token']}


def test_account_lifecycle(live):
    client, db = live
    correo, auth = cuenta(client)
    assert client.post('/ciudadano/registro', json={'correo': correo.upper(), 'contrasena': 'Una frase de prueba 2026'}).status_code == 409
    assert client.post('/ciudadano/login', json={'correo': correo, 'contrasena': 'incorrecta'}).status_code == 401
    assert client.post('/ciudadano/login', json={'correo': 'nadie@example.com', 'contrasena': 'x'}).status_code == 401
    login = client.post('/ciudadano/login', json={'correo': correo.upper(), 'contrasena': 'Una frase de prueba 2026'})
    assert login.status_code == 200 and login.json()['correo'] == correo
    # Cuenta nueva: perfil vacío con su correo y sin solicitudes.
    assert client.get('/ciudadano/perfil', headers=auth).json()['correo'] == correo
    assert client.get('/ciudadano/solicitudes', headers=auth).json() == {'items': []}
    assert client.get('/ciudadano/perfil').status_code == 401
    assert client.post('/ciudadano/logout', headers=auth).status_code == 204
    assert client.get('/ciudadano/perfil', headers=auth).status_code == 401
    assert client.post('/ciudadano/recuperar', json={'correo': correo}).status_code == 202


def test_request_is_written_to_ssnl_and_seen_by_executive(live):
    client, db = live
    _, auth = cuenta(client)
    curp = curp_nueva()
    datos = solicitud()
    datos['beneficiario']['curp'] = curp
    body = {'idempotencia': str(uuid.uuid4()), 'solicitud': datos}
    # Sin perfil completo no se puede enviar.
    assert client.post('/ciudadano/solicitudes', headers=auth, json=body).status_code == 409
    assert client.put('/ciudadano/perfil', headers=auth, json=PERFIL).status_code == 200
    r = client.post('/ciudadano/solicitudes', headers=auth, json=body)
    assert r.status_code == 201, r.text
    nueva = r.json()
    assert nueva['folio'].startswith('Solicitud #') and nueva['estatus'] == 'recibida'
    assert nueva['tipoApoyo'] == 'Andadera o bastón' and nueva['beneficiario']['nombres'] == 'José'
    assert [e['estatus'] for e in nueva['historial']] == ['recibida']
    # Reintento con la misma clave: no se duplica.
    assert client.post('/ciudadano/solicitudes', headers=auth, json=body).json()['folio'] == nueva['folio']
    sid = int(nueva['folio'].split('#')[1])
    row = db.execute(text('''SELECT sa.solapoyo_descripcion AS descripcion, sa.solapoyo_observaciones AS obs,
      ta.descripcion AS tipo, st.descripcion AS estatus, cr.descripcion AS canal, b.ben_gen_curp AS curp,
      b.ben_gen_age AS edad, g.descripcion AS sexo, gv.descripcion AS grupo, m.cve_mun AS mun_nac,
      dom.nom_mun AS municipio, s.sol_telefono AS telefono, p.descripcion AS parentesco
      FROM Tbl_SolicitudesApoyo sa JOIN Cat_TipoApoyo ta ON ta.id=sa.solapoyo_tipoapoyoid
      JOIN Cat_StatusAtencion st ON st.id=sa.solapoyo_statusid JOIN Cat_CanalesRecepcion cr ON cr.id=sa.solapoyo_canalrecepcionid
      JOIN Tbl_Beneficiarios b ON b.ben_id=sa.solapoyo_beneficiarioid JOIN Cat_Generos g ON g.id=b.ben_gen_sex
      JOIN Cat_GruposVulnerables gv ON gv.id=b.ben_misc_grupovulnerable_id
      JOIN INEGI_Cat_Municipios m ON m.id=b.ben_gen_municipio_nacimiento
      JOIN INEGI_Cat_Municipios dom ON dom.id=b.ben_dom_municipio AND dom.entidad_id=b.ben_dom_entidad
      JOIN Tbl_Solicitantes s ON s.sol_id=sa.solapoyo_solicitanteid JOIN Cat_Parentescos p ON p.id=s.sol_parentescoid
      WHERE sa.solapoyo_id=:id'''), {'id': sid}).mappings().one()
    assert row['tipo'] == 'Equipos y aparatos' and row['estatus'] == 'Inicio' and row['canal'] == svc.CANAL
    assert row['curp'] == curp and row['sexo'] == 'Masculino' and row['edad'] >= 68
    assert row['grupo'] == 'Sí, Adulto Mayor' and row['mun_nac'] == '999' and row['municipio'] == 'Monterrey'
    assert row['parentesco'] == 'Hijo / Hija' and row['telefono'] == '8112345678'
    assert row['descripcion'].startswith('Solicitud de andadera') and 'receta.pdf' in row['obs']
    # Cambiar el celular del perfil se refleja en SSNL.
    assert client.put('/ciudadano/perfil', headers=auth, json={**PERFIL, 'celular': '81 8765 4321'}).status_code == 200
    assert db.execute(text('SELECT sol_telefono FROM Tbl_Solicitantes s JOIN Tbl_SolicitudesApoyo sa '
                           'ON sa.solapoyo_solicitanteid=s.sol_id WHERE sa.solapoyo_id=:id'), {'id': sid}).scalar() == '8187654321'
    # Cuando el personal cambia el estatus, la app lo ve con su historial.
    db.execute(text("UPDATE Tbl_SolicitudesApoyo SET solapoyo_statusid=(SELECT id FROM Cat_StatusAtencion "
                    "WHERE descripcion='No es competencia') WHERE solapoyo_id=:id"), {'id': sid})
    lista = client.get('/ciudadano/solicitudes', headers=auth).json()['items']
    assert len(lista) == 1 and lista[0]['estatus'] == 'noEsCompetencia'
    assert [e['estatus'] for e in lista[0]['historial']] == ['recibida', 'noEsCompetencia']
    # Otra cuenta no ve esa solicitud.
    _, otra = cuenta(client)
    assert client.get('/ciudadano/solicitudes', headers=otra).json() == {'items': []}
    # Borrar la cuenta elimina su solicitud y las personas que solo ella usaba.
    cid = db.execute(text('SELECT cuenta_id FROM ciudadano_solicitud WHERE solicitud_id=:id'), {'id': sid}).scalar()
    assert svc.borrar_cuenta(db, cid) == 1
    assert db.execute(text('SELECT COUNT(*) FROM Tbl_SolicitudesApoyo WHERE solapoyo_id=:id'), {'id': sid}).scalar() == 0
    assert db.execute(text('SELECT COUNT(*) FROM Tbl_Beneficiarios WHERE ben_gen_curp=:c'), {'c': curp}).scalar() == 0


def test_request_validation(live):
    client, db = live
    _, auth = cuenta(client)
    client.put('/ciudadano/perfil', headers=auth, json=PERFIL)
    malo = solicitud(tipoApoyo='Inventado')
    assert client.post('/ciudadano/solicitudes', headers=auth,
                       json={'idempotencia': str(uuid.uuid4()), 'solicitud': malo}).status_code == 422
    sin_curp = solicitud(beneficiario={'esTitular': False, 'nombres': 'X', 'primerApellido': 'Y', 'relacion': 'Tío', 'curp': ''})
    assert client.post('/ciudadano/solicitudes', headers=auth,
                       json={'idempotencia': str(uuid.uuid4()), 'solicitud': sin_curp}).status_code == 422


def test_netlify_web_version_is_allowed_by_cors():
    with TestClient(app) as client:
        r = client.options('/ciudadano/login', headers={'Origin': 'https://sieasas-ciudadano.netlify.app',
                                                         'Access-Control-Request-Method': 'POST'})
        assert r.headers.get('access-control-allow-origin') == 'https://sieasas-ciudadano.netlify.app'
        otro = client.options('/ciudadano/login', headers={'Origin': 'https://ejemplo-malicioso.com',
                                                            'Access-Control-Request-Method': 'POST'})
        assert 'access-control-allow-origin' not in otro.headers


def test_password_recovery_with_emailed_code(live, monkeypatch):
    from contextlib import contextmanager
    from app.routers import ciudadano as router
    client, db = live
    correo, auth = cuenta(client)
    enviados = []

    @contextmanager
    def misma_sesion():
        yield db
    monkeypatch.setattr(router, 'SessionLocal', misma_sesion)
    monkeypatch.setattr(router, 'smtp_configurado', lambda: True)
    monkeypatch.setattr(router, 'mensaje_codigo_ciudadano', lambda destino, codigo, minutos: (destino, codigo))
    monkeypatch.setattr(router, 'enviar', enviados.append)

    # Un correo sin cuenta recibe un aviso claro y no se envía nada.
    r = client.post('/ciudadano/recuperar', json={'correo': 'nadie@example.com'})
    assert r.status_code == 404 and 'No existe una cuenta' in r.json()['detail']
    assert enviados == []
    assert client.post('/ciudadano/recuperar', json={'correo': correo}).status_code == 202
    destino, codigo = enviados[-1]
    assert destino == correo and len(codigo) == 6 and codigo.isdigit()

    nueva = 'Otra frase de prueba distinta 2026'
    incorrecto = '000000' if codigo != '000000' else '111111'
    r = client.post('/ciudadano/restablecer', json={'correo': correo, 'codigo': incorrecto, 'contrasena': nueva})
    assert r.status_code == 400
    r = client.post('/ciudadano/restablecer', json={'correo': correo, 'codigo': codigo, 'contrasena': nueva})
    assert r.status_code == 200, r.text
    # La sesión anterior se cierra; la nueva contraseña funciona y el código ya no sirve.
    assert client.get('/ciudadano/perfil', headers=auth).status_code == 401
    assert client.post('/ciudadano/login', json={'correo': correo, 'contrasena': nueva}).status_code == 200
    assert client.post('/ciudadano/login', json={'correo': correo, 'contrasena': 'Una frase de prueba 2026'}).status_code == 401
    assert client.post('/ciudadano/restablecer', json={'correo': correo, 'codigo': codigo, 'contrasena': nueva}).status_code == 400


def test_recovery_code_is_blocked_after_failed_attempts(live, monkeypatch):
    from contextlib import contextmanager
    from app.routers import ciudadano as router
    client, db = live
    correo, _ = cuenta(client)
    enviados = []

    @contextmanager
    def misma_sesion():
        yield db
    monkeypatch.setattr(router, 'SessionLocal', misma_sesion)
    monkeypatch.setattr(router, 'smtp_configurado', lambda: True)
    monkeypatch.setattr(router, 'mensaje_codigo_ciudadano', lambda destino, codigo, minutos: (destino, codigo))
    monkeypatch.setattr(router, 'enviar', enviados.append)
    monkeypatch.setattr(router, 'limit_request', lambda *a, **k: None)
    client.post('/ciudadano/recuperar', json={'correo': correo})
    codigo = enviados[-1][1]
    malo = '000000' if codigo != '000000' else '111111'
    for _ in range(router.INTENTOS_CODIGO):
        client.post('/ciudadano/restablecer', json={'correo': correo, 'codigo': malo, 'contrasena': 'x' * 20})
    # Agotados los intentos, ni el código correcto funciona.
    assert client.post('/ciudadano/restablecer', json={'correo': correo, 'codigo': codigo, 'contrasena': 'x' * 20}).status_code == 400


def test_recovery_needs_mail_service(monkeypatch):
    from app.routers import ciudadano as router
    monkeypatch.setattr(router, 'smtp_configurado', lambda: False)
    if os.getenv('RUN_DB_TESTS') != '1':
        pytest.skip('Set RUN_DB_TESTS=1 to run transaction-isolated MySQL tests.')
    with TestClient(app) as client:
        assert client.post('/ciudadano/recuperar', json={'correo': 'nadie@example.com'}).status_code == 503


def test_recovery_tells_when_email_has_no_account(monkeypatch):
    # Sin MySQL: la sesión simulada responde si el correo tiene cuenta.
    from app.routers import ciudadano as router

    class SesionFalsa:
        def __init__(self, existe):
            self.existe = existe

        def execute(self, *_):
            return self

        def scalar(self):
            return 1 if self.existe else None

    class TareasFalsas:
        def __init__(self):
            self.tareas = []

        def add_task(self, funcion, *args):
            self.tareas.append((funcion, args))

    monkeypatch.setattr(router, 'limit_request', lambda *a, **k: None)
    monkeypatch.setattr(router, 'smtp_configurado', lambda: True)

    tareas = TareasFalsas()
    with pytest.raises(HTTPException) as error:
        router.recuperar(router.Correo(correo='nadie@example.com'), None, tareas, SesionFalsa(False))
    assert error.value.status_code == 404 and 'No existe una cuenta' in error.value.detail
    assert tareas.tareas == []

    assert router.recuperar(router.Correo(correo='Ana@Example.com'), None, tareas, SesionFalsa(True)) == router.ENVIADO
    assert tareas.tareas == [(router.enviar_codigo, (router.normalizar('Ana@Example.com'),))]


def test_code_email_contains_code(monkeypatch):
    from app.services.auth_service import mensaje_codigo_ciudadano
    monkeypatch.setenv('SMTP_HOST', 'smtp.example.com')
    monkeypatch.setenv('SMTP_FROM', 'SIESAS <no-responder@example.com>')
    mensaje = mensaje_codigo_ciudadano('ana@example.com', '123456', 15)
    assert mensaje['To'] == 'ana@example.com' and '123456' in mensaje['Subject']
    assert '123456' in mensaje.get_body(('plain',)).get_content()
    assert '123456' in mensaje.get_body(('html',)).get_content()
