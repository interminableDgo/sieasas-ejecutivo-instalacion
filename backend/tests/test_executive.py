import io
import os
import uuid
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from openpyxl import load_workbook
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.main import app
from app.database import engine, get_db
from app.security import hasher, issue_token, now
from app.services import executive_service as svc
from app.services.executive_service import DATES, looks_like_date, matches, month_series, where_clause
from app.routers.executive import NewRequest


def test_months_zero_fill_and_year_boundary():
    result=month_series([{'mes':'2026-01','recibidas':2,'resueltas':1}],date(2026,2,1))
    assert len(result)==12
    assert result[0]['mes']=='2025-03'
    assert result[-2]['recibidas']==2
    assert result[-1]['recibidas']==0


def test_scope_always_applied_and_parameterized():
    where, params=where_clause({'entidad_id':7},{'municipio_id':12,'dependencia_id':3})
    assert 'm.entidad_id=:entidad_id' in where
    assert params=={'entidad_id':7,'municipio_id':12,'dependencia_id':3}


def test_multiple_values_are_alternatives_within_a_filter():
    where, params=where_clause({'entidad_id':7},{'municipio_id':[12,15],'estatus_id':1})
    assert 'm.id IN (:municipio_id_0,:municipio_id_1)' in where
    assert 'sa.solapoyo_statusid=:estatus_id' in where
    assert 'm.entidad_id=:entidad_id' in where
    assert params=={'entidad_id':7,'municipio_id_0':12,'municipio_id_1':15,'estatus_id':1}


def test_filters_accept_repeated_params_and_reject_invalid():
    from app.services.executive_service import filters
    assert filters(municipio_id=[3,3],estatus_id=[1,5])=={'municipio_id':3,'estatus_id':[1,5]}
    assert filters()=={}
    with pytest.raises(Exception):
        filters(municipio_id=[0])
    with pytest.raises(Exception):
        filters(tipo_apoyo_id=list(range(1,102)))


def test_search_words_are_parameterized_and_dates_need_a_date_shape():
    sql,params=matches(['name'],['50%_off'],'q')
    assert params=={'q0':'%50\\%\\_off%'} and '50' not in sql
    assert looks_like_date('29/02/2024') and looks_like_date('2024-02') and looks_like_date('2024')
    assert not looks_like_date('026') and not looks_like_date('maria')
    sql,_=matches(['name',*DATES],['026'],'q')
    assert 'DATE_FORMAT' not in sql
    sql,_=matches(['name'],['oct'],'q',months=True)
    assert 'MONTH(sa.created)=10' in sql
    sql,params=matches(['name'],['#14'],'q',folio=True)
    assert 'sa.solapoyo_id=:q0_folio' in sql and params['q0_folio']==14
    assert 'solapoyo_id' not in matches(['name'],['jorge'],'q',folio=True)[0]


def test_blank_request_rejected():
    with pytest.raises(ValueError):
        NewRequest(nombres=' ',apellidos='A',municipio_id=1,tipo_apoyo_id=1,dependencia_id=1,descripcion='x',idempotencia=uuid.uuid4())


@pytest.fixture
def live():
    if os.getenv('RUN_DB_TESTS')!='1':
        pytest.skip('Set RUN_DB_TESTS=1 to run transaction-isolated MySQL tests.')
    connection=engine.connect()
    transaction=connection.begin()
    connection.exec_driver_sql('START TRANSACTION')
    db=Session(bind=connection,join_transaction_mode='create_savepoint')
    address=f'codex-test-{uuid.uuid4().hex}@example.com'
    password='Una frase de prueba segura 2026'
    uid=db.execute(text("INSERT INTO Tbl_Users (us_name,us_lastname,us_email,us_account,us_pwd,us_phone,us_rol,is_active,createdBy,updatedBy) VALUES (:n,:a,:e,:e,:p,'','Ejecutivo',1,0,0)"),
      {'n':'Prueba temporal','a':'Transacción','e':address,'p':hasher.hash(password)}).lastrowid
    eid=db.execute(text("SELECT id FROM INEGI_Cat_Entidades WHERE cve_ent='19'")).scalar_one()
    db.execute(text("INSERT INTO auth_assignment (item_name,user_id,created_at) VALUES ('Ejecutivo',:u,UNIX_TIMESTAMP())"),{'u':str(uid)})
    db.execute(text('INSERT INTO ejecutivo_acceso (usuario_id,entidad_id) VALUES (:u,:e)'),{'u':uid,'e':eid})
    db.commit()
    def override():
        yield db
    app.dependency_overrides[get_db]=override
    with TestClient(app) as client:
        try:
            yield client,db,uid,address,password,eid
        finally:
            app.dependency_overrides.clear()
            db.close()
            transaction.rollback()
            connection.close()


def sign_in(client,address,password):
    result=client.post('/auth/login',json={'correo':address,'password':password})
    assert result.status_code==200,result.text
    token=result.json()['token']
    return {'Authorization':'Bearer '+token}


def test_comparison_api_auth_validation_and_empty_scope(live):
    client,db,uid,address,password,eid=live
    params={'inicio':['2024-02-01','2025-02-01','2026-02-01'],'fin':['2024-02-29','2025-02-28','2026-02-28'],'municipio_id':2147483647}
    assert client.get('/ejecutivo/comparacion',params=params).status_code==401
    headers=sign_in(client,address,password)
    response=client.get('/ejecutivo/comparacion',params=params,headers=headers)
    assert response.status_code==200
    periods=response.json()['periodos']
    assert [p['total'] for p in periods]==[0,0,0]
    assert periods[0]['variacion'] is None and periods[2]['variacion']['total']['porcentaje']==0
    assert client.get('/ejecutivo/comparacion',params={**params,'fin':['2024-01-01','2025-02-28','2026-02-28']},headers=headers).status_code==422
    assert client.get('/ejecutivo/comparacion',params={**params,'fin':params['fin'][:2]},headers=headers).status_code==422


def test_empty_data_scope_registration_exports_and_logout(live):
    client,db,uid,address,password,eid=live
    assert client.get('/ejecutivo/dashboard').status_code==401
    headers=sign_in(client,address,password)
    initial=client.get('/ejecutivo/dashboard',headers=headers)
    assert initial.status_code==200,initial.text
    before=initial.json()['total']
    cats=client.get('/ejecutivo/catalogos',headers=headers).json()
    mid,other_mid=cats['municipios'][0]['id'],cats['municipios'][1]['id']
    home=db.execute(text("INSERT INTO Cat_Colonias (municipio_id,nombre,codigo_postal) VALUES (:m,'Colonia temporal','64999')"),{'m':mid}).lastrowid
    away=db.execute(text("INSERT INTO Cat_Colonias (municipio_id,nombre,codigo_postal) VALUES (:m,'Colonia temporal','65999')"),{'m':other_mid}).lastrowid
    db.commit()
    # La misma colonia con otra escritura (mayúsculas o acentos) no puede repetirse en el catálogo.
    with pytest.raises(IntegrityError):
        db.execute(text("INSERT INTO Cat_Colonias (municipio_id,nombre,codigo_postal) VALUES (:m,'COLONIA TEMPORÁL','64999')"),{'m':mid})
    db.rollback()
    colonies=client.get('/ejecutivo/colonias',params={'municipio_id':mid},headers=headers).json()['items']
    assert {'id':home,'nombre':'Colonia temporal','codigo_postal':'64999'} in colonies
    data={'beneficiario':{'nombres':'Beneficiario temporal','apellidos':'Prueba',
      'fecha_nacimiento':'1990-01-01','genero_id':cats['generos'][0]['id'],
      'municipio_nacimiento_id':mid,'municipio_id':mid,'calle':'Temporal','numero':'1','colonia_id':home,
      'tiempo_residencia':1,'con_quien_vive_id':cats['con_quien_vive'][0]['id'],'numero_hijos':0,
      'estudia':True,'area_estudio_id':cats['areas_estudio'][0]['id'],'ocupacion_id':cats['ocupaciones'][0]['id'],
      'seguridad_social_id':cats['seguridad_social'][0]['id'],'grupo_vulnerable_id':cats['grupos'][0]['id']},
      'solicitante':{'nombres':'Solicitante temporal','apellidos':'Prueba',
      'parentesco_id':cats['parentescos'][0]['id'],'fecha_nacimiento':'1990-01-01',
      'mismo_domicilio':True,'telefono':'8112345678'},
      'tipo_apoyo_id':cats['apoyos'][0]['id'],'dependencia_id':cats['dependencias'][0]['id'],
      'enviado_por_id':cats['origenes'][0]['id'],'canal_id':cats['canales'][0]['id'],
      'unidad_tratante_id':cats['unidades'][0]['id'],'descripcion':'Prueba aislada, se revierte',
      'idempotencia':str(uuid.uuid4())}
    created=client.post('/ejecutivo/solicitudes',json=data,headers=headers)
    assert created.status_code==201,created.text
    assert client.post('/ejecutivo/solicitudes',json=data,headers=headers).json()==created.json()
    sid=created.json()['solicitud_id']
    stored=db.execute(text('''SELECT b.ben_dom_colonia,b.ben_dom_colonia_id,b.ben_dom_cp,b.ben_estsocioeco_conquienvive,
      s.sol_calle,s.sol_colonia,s.sol_colonia_id,s.sol_codigopostal,s.sol_municipioid
      FROM Tbl_SolicitudesApoyo sa JOIN Tbl_Beneficiarios b ON b.ben_id=sa.solapoyo_beneficiarioid
      JOIN Tbl_Solicitantes s ON s.sol_id=sa.solapoyo_solicitanteid WHERE sa.solapoyo_id=:sid'''),{'sid':sid}).mappings().one()
    assert (stored['ben_dom_colonia'],stored['ben_dom_colonia_id'],stored['ben_dom_cp'])==(home,home,'64999')
    assert stored['ben_estsocioeco_conquienvive']==cats['con_quien_vive'][0]['nombre']
    assert (stored['sol_calle'],stored['sol_colonia_id'],stored['sol_codigopostal'],stored['sol_municipioid'])==('Temporal',home,'64999',mid)
    wrong=client.post('/ejecutivo/solicitudes',json={**data,'beneficiario':{**data['beneficiario'],'colonia_id':away},
      'idempotencia':str(uuid.uuid4())},headers=headers)
    assert wrong.status_code==422 and 'colonia' in wrong.text
    summary=client.get('/ejecutivo/dashboard',headers=headers).json()
    assert summary['total']==before+1
    # The status breakdown shown under the total adds up to it.
    assert sum(summary[k] for k in ['activas','resueltas','no_competencia','canceladas'])==summary['total']
    assert sum(r['total'] for r in summary['municipios'])==summary['total']
    assert sum(r['total'] for r in summary['grupos'])==summary['total']
    db.execute(text("UPDATE Tbl_SolicitudesApoyo SET created='2024-02-29 12:00:00', solapoyo_statusid=(SELECT id FROM Cat_StatusAtencion WHERE descripcion='Resuelto') WHERE solapoyo_id=:sid"),{'sid':sid})
    db.commit()
    comparison=client.get('/ejecutivo/comparacion',params={'inicio':['2024-02-01','2025-02-01'],'fin':['2024-02-29','2025-02-28'],'municipio_id':mid},headers=headers).json()
    first,second=comparison['periodos']
    assert first['total']==1 and first['resueltas']==1 and first['activas']==0
    assert second['total']==0
    assert second['variacion']['total']['porcentaje']==-100.0
    # Búsqueda de la tabla: sin importar acentos ni mayúsculas, por persona o por fecha de registro.
    def search(q,**extra):
        result=client.get('/ejecutivo/solicitudes',params={'q':q,'municipio_id':mid,**extra},headers=headers)
        assert result.status_code==200,result.text
        return [r['solicitud_id'] for r in result.json()['items']]
    assert sid in search('BENEFICIARIO TEMPORÁL prúeba')
    assert sid in search('solicitante temporal')
    assert sid in search('29/02/2024') and sid in search('2024-02-29') and sid in search('febrero 2024')
    assert sid not in search('Beneficiario temporal 2023')
    # Sorting by column covers every page, not only the one on screen.
    def column(orden,direccion):
        result=client.get('/ejecutivo/solicitudes',params={'orden':orden,'direccion':direccion},headers=headers)
        assert result.status_code==200,result.text
        return [r['solicitud_id'] for r in result.json()['items']]
    assert column('solicitud','asc')==sorted(column('solicitud','asc'))
    assert column('solicitud','desc')==sorted(column('solicitud','desc'),reverse=True)
    for orden in svc.SORT_COLUMNS:
        assert column(orden,'asc') is not None
    assert client.get('/ejecutivo/solicitudes',params={'orden':'sa.created; DROP'},headers=headers).status_code==422
    row=client.get('/ejecutivo/solicitudes',params={'q':'temporal','municipio_id':mid},headers=headers).json()['items'][0]
    assert (row['beneficiario'],row['solicitante'])==('Beneficiario temporal Prueba','Solicitante temporal Prueba')
    # Tipo de apoyo, estatus y folio distinguen solicitudes de la misma persona.
    support=cats['apoyos'][0]['nombre']
    assert sid in search('beneficiario temporal '+support.split()[0].upper())
    assert sid in search('temporal resuelto') and sid in search(f'#{sid}') and sid in search(f'temporal {sid}')
    hints=client.get('/ejecutivo/solicitudes/sugerencias',params={'q':'TEMPORÁL','municipio_id':mid},headers=headers)
    assert hints.status_code==200,hints.text
    hints=hints.json()
    assert hints['total']>=1 and len(hints['solicitudes'])<=5
    first=hints['solicitudes'][0]
    assert (first['solicitud_id'],first['tipo_apoyo'],first['estatus'])==(sid,support,'Resuelto')
    people={(p['nombre'],p['tipo']):p['total'] for p in hints['personas']}
    assert people[('Beneficiario temporal Prueba','Beneficiario')]==1
    assert people[('Solicitante temporal Prueba','Solicitante')]==1
    # A word of the applicant's name does not offer the beneficiary ("jorge serangue").
    narrowed=client.get('/ejecutivo/solicitudes/sugerencias',params={'q':'temporal solicitante','municipio_id':mid},headers=headers).json()
    assert sid in [r['solicitud_id'] for r in narrowed['solicitudes']]
    assert [(p['nombre'],p['tipo']) for p in narrowed['personas']]==[('Solicitante temporal Prueba','Solicitante')]
    # Request details still narrow a person: "temporal resuelto" keeps both.
    both={p['tipo'] for p in client.get('/ejecutivo/solicitudes/sugerencias',params={'q':'temporal resuelto','municipio_id':mid},headers=headers).json()['personas']}
    assert both=={'Beneficiario','Solicitante'}
    dates=client.get('/ejecutivo/solicitudes/sugerencias',params={'q':'29/02','municipio_id':mid},headers=headers).json()
    assert sid in [r['solicitud_id'] for r in dates['solicitudes']] and dates['personas']==[]
    found=client.get('/ejecutivo/personas',params={'tipo':'beneficiario','q':'Beneficiario temporal'},headers=headers)
    assert found.status_code==200 and found.json()['items']
    # Same names are told apart by birth date, municipality, requests and phone.
    person=next(p for p in found.json()['items'] if p['nombre'].startswith('Beneficiario temporal Prueba'))
    assert (str(person['fecha_nacimiento']),person['solicitudes'])==('1990-01-01',1) and person['municipio']
    by_phone=client.get('/ejecutivo/personas',params={'tipo':'solicitante','q':'8112345678'},headers=headers).json()['items']
    assert any(p['nombre'].startswith('Solicitante temporal Prueba') and p['telefono']=='8112345678' for p in by_phone)
    # Palabras en cualquier orden, sin importar acentos ni mayúsculas.
    for tipo,q in [('beneficiario','PRUEBA temporál beneficiario'),('solicitante','prueba SOLICITANTE')]:
        names=[p['nombre'] for p in client.get('/ejecutivo/personas',params={'tipo':tipo,'q':q},headers=headers).json()['items']]
        assert any(n.startswith(tipo.capitalize()+' temporal Prueba') for n in names),(q,names)
    assert client.get('/ejecutivo/dashboard?region_id=1',headers=headers).status_code==422
    filtered=client.get('/ejecutivo/dashboard?municipio_id=2147483647',headers=headers).json()
    assert filtered['total']==0
    assert 'regiones' not in filtered
    assert len(filtered['tendencia'])==12
    assert client.get(f'/ejecutivo/solicitudes/{sid}',headers=headers).json()['nombres']==data['beneficiario']['nombres']
    assert client.get('/ejecutivo/solicitudes/2147483647',headers=headers).status_code==404
    assert client.get('/ejecutivo/dashboard?fecha_inicio=2026-12-01&fecha_fin=2026-01-01',headers=headers).status_code==422
    assert client.post('/ejecutivo/solicitudes',json={**data,'beneficiario':{**data['beneficiario'],'municipio_id':2147483647},'idempotencia':str(uuid.uuid4())},headers=headers).status_code==422
    for fmt in ['xlsx','pdf']:
        report=client.get('/ejecutivo/exportar/'+fmt,headers=headers)
        assert report.status_code==200,report.text[:200]
        assert report.content.startswith(b'PK' if fmt=='xlsx' else b'%PDF')
        if fmt=='xlsx':
            book=load_workbook(io.BytesIO(report.content))
            assert 'Solicitudes' not in book.sheetnames
            label=next(c for row in book['Resumen'] for c in row if c.value=='Solicitudes')
            assert book['Resumen'].cell(label.row+1,label.column).value==before+1
    # An account assigned to another entity cannot see or register NL requests.
    other=db.execute(text("SELECT id FROM INEGI_Cat_Entidades WHERE cve_ent='01'")).scalar_one()
    db.execute(text('UPDATE ejecutivo_acceso SET entidad_id=:e WHERE usuario_id=:u'),{'e':other,'u':uid})
    db.commit()
    assert client.get(f'/ejecutivo/solicitudes/{sid}',headers=headers).status_code==404
    assert client.get('/ejecutivo/dashboard',headers=headers).json()['total']==0
    assert client.post('/ejecutivo/solicitudes',json={**data,'idempotencia':str(uuid.uuid4())},headers=headers).status_code==422
    assert client.post('/auth/logout',headers=headers).status_code==200
    assert client.get('/auth/me',headers=headers).status_code==401


def test_reset_single_use_expiry_revocation(live):
    client,db,uid,address,password,eid=live
    headers=sign_in(client,address,password)
    token=issue_token(db,uid,'reset',30)
    expired=issue_token(db,uid,'reset',-1)
    db.commit()
    new_password='Otra frase de prueba segura 2026'
    assert client.post('/auth/reset-password',json={'token':expired,'password':new_password}).status_code==400
    body={'token':token,'password':new_password}
    assert client.post('/auth/reset-password',json=body).status_code==200
    assert client.post('/auth/reset-password',json=body).status_code==400
    assert client.get('/auth/me',headers=headers).status_code==401
    assert client.post('/auth/login',json={'correo':address,'password':password}).status_code==401
    assert client.post('/auth/login',json={'correo':address,'password':new_password}).status_code==200


def test_2fa_and_replay(live):
    import pyotp
    from app.security import cipher
    client,db,uid,address,password,eid=live
    secret=pyotp.random_base32()
    db.execute(text('UPDATE ejecutivo_acceso SET totp_secret=:s WHERE usuario_id=:u'),{'s':cipher().encrypt(secret.encode()).decode(),'u':uid})
    db.commit()
    result=client.post('/auth/login',json={'correo':address,'password':password}).json()
    assert result['requires_2fa'] is True
    token=result['token']
    assert client.get('/auth/me',headers={'Authorization':'Bearer '+token}).status_code==401
    body={'token':token,'code':pyotp.TOTP(secret).now()}
    response=client.post('/auth/verify',json=body)
    assert response.status_code==200,response.text
    assert client.post('/auth/verify',json=body).status_code==400


def test_missing_mail_and_inactive_user(live,monkeypatch):
    client,db,uid,address,password,eid=live
    monkeypatch.delenv('SMTP_HOST',raising=False)
    assert client.post('/auth/forgot-password',json={'correo':address}).status_code==503
    db.execute(text('UPDATE Tbl_Users SET is_active=0 WHERE us_id=:u'),{'u':uid})
    db.commit()
    assert client.post('/auth/login',json={'correo':address,'password':password}).status_code==401
