from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session

from app.database import get_db
from app.security import current_user
from app.services import executive_service as svc
from app.services.executive_report import build_report, render_pdf, render_xlsx
from app.services.ssnl_registration import NewRequest, create_request as save_ssnl_request

router=APIRouter(prefix='/ejecutivo',tags=['Ejecutivo'])


CATALOGS = {'apoyos':'Cat_TipoApoyo','dependencias':'Cat_Dependencias','grupos':'Cat_GruposVulnerables',
 'estatus':'Cat_StatusAtencion','canales':'Cat_CanalesRecepcion','origenes':'Cat_EnviadoPor',
 'unidades':'Cat_UnidadesTratantes','parentescos':'Cat_Parentescos','generos':'Cat_Generos',
 'seguridad_social':'Cat_SeguridadSocial','partidos':'Cat_PartidosPoliticos',
 'con_quien_vive':'Cat_ConQuienVive','ocupaciones':'Cat_Ocupaciones','fuentes_ingreso':'Cat_FuentesIngreso',
 'areas_estudio':'Cat_AreasEstudio'}

@router.get('/catalogos')
def catalogs(user=Depends(current_user),db:Session=Depends(get_db)):
    result={key:svc.query_rows(db,f'SELECT id,descripcion AS nombre FROM `{table}` WHERE is_active=1 ORDER BY descripcion',{})
      for key,table in CATALOGS.items()}
    result['municipios']=svc.query_rows(db,'SELECT id,nom_mun AS nombre,cvegeo AS clave_inegi FROM INEGI_Cat_Municipios WHERE entidad_id=:eid ORDER BY nom_mun',{'eid':user['entidad_id']})
    result['entidades']=svc.query_rows(db,'SELECT id,nom_ent AS nombre FROM INEGI_Cat_Entidades ORDER BY nom_ent',{})
    return result


@router.get('/municipios-nacimiento')
def birth_municipalities(entidad_id:int=Query(gt=0),user=Depends(current_user),db:Session=Depends(get_db)):
    return {'items':svc.query_rows(db,'SELECT id,nom_mun AS nombre FROM INEGI_Cat_Municipios WHERE entidad_id=:eid ORDER BY nom_mun',{'eid':entidad_id})}


@router.get('/colonias')
def colonies(municipio_id:int=Query(gt=0),user=Depends(current_user),db:Session=Depends(get_db)):
    # Solo municipios del estado autorizado; el código postal sale del catálogo, no de la captura.
    return {'items':svc.query_rows(db,'''SELECT c.id,c.nombre,c.codigo_postal FROM Cat_Colonias c
      JOIN INEGI_Cat_Municipios m ON m.id=c.municipio_id
      WHERE c.municipio_id=:mid AND m.entidad_id=:eid AND c.is_active=1 ORDER BY c.nombre,c.codigo_postal''',
      {'mid':municipio_id,'eid':user['entidad_id']})}


@router.get('/personas')
def people(tipo:Literal['beneficiario','solicitante'],q:str=Query('',max_length=150),
    user=Depends(current_user),db:Session=Depends(get_db)):
    if tipo=='beneficiario':
        sql="""SELECT b.ben_id AS id, CONCAT(b.ben_gen_name,' ',b.ben_gen_lastname,' · #',b.ben_id) AS nombre
          FROM Tbl_Beneficiarios b JOIN INEGI_Cat_Municipios m ON m.id=b.ben_dom_municipio AND m.entidad_id=b.ben_dom_entidad
          WHERE b.is_active=1 AND b.ben_dom_entidad=:eid
          AND (CONCAT(b.ben_gen_name,' ',b.ben_gen_lastname) LIKE :q OR b.ben_gen_curp=:exact)
          ORDER BY b.ben_gen_name,b.ben_id LIMIT 30"""
    else:
        sql="""SELECT s.sol_id AS id, CONCAT(s.sol_nombres,' ',s.sol_apellidos,' · #',s.sol_id) AS nombre
          FROM Tbl_Solicitantes s JOIN INEGI_Cat_Municipios m ON m.id=s.sol_municipioid AND m.entidad_id=s.sol_estadoid
          WHERE s.is_active=1 AND s.sol_estadoid=:eid
          AND CONCAT(s.sol_nombres,' ',s.sol_apellidos) LIKE :q ORDER BY s.sol_nombres,s.sol_id LIMIT 30"""
    return {'items':svc.query_rows(db,sql,{'eid':user['entidad_id'],'q':'%'+q.strip()+'%','exact':q.strip()})}


@router.get('/dashboard')
def dashboard(selected=Depends(svc.filters),user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.dashboard(db,user,selected)


@router.get('/comparacion')
def comparison(a_inicio:date, a_fin:date, b_inicio:date, b_fin:date,
    selected=Depends(svc.filters),user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.compare_periods(db,user,selected,a_inicio,a_fin,b_inicio,b_fin)


@router.get('/solicitudes')
def requests(selected=Depends(svc.filters),page:int=Query(0,ge=0),q:str|None=Query(None,max_length=80),
    user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.list_rows(db,user,selected,10,page*10,q)


# Declared before /solicitudes/{sid} so "sugerencias" is not read as an id.
@router.get('/solicitudes/sugerencias')
def request_suggestions(q:str=Query(...,min_length=1,max_length=80),selected=Depends(svc.filters),
    user=Depends(current_user),db:Session=Depends(get_db)):
    return {'items': svc.suggestions(db,user,selected,q)}


@router.get('/solicitudes/{sid}')
def detail(sid:int,user=Depends(current_user),db:Session=Depends(get_db)):
    where,params=svc.where_clause(user,{})
    rows=svc.query_rows(db,svc.ROW_SELECT+""", sa.solapoyo_descripcion AS descripcion,sa.solapoyo_observaciones AS observaciones,
      b.ben_gen_name AS nombres,b.ben_gen_lastname AS apellidos,
      c.descripcion AS canal,ut.descripcion AS unidad_tratante,o.descripcion AS origen,
      CONCAT(s.sol_nombres,' ',s.sol_apellidos) AS solicitante"""+svc.JOINS+
      ' JOIN Cat_CanalesRecepcion c ON c.id=sa.solapoyo_canalrecepcionid'
      ' JOIN Cat_UnidadesTratantes ut ON ut.id=sa.solapoyo_unidadtratanteid'
      ' JOIN Cat_EnviadoPor o ON o.id=sa.solapoyo_enviadoporid'
      ' JOIN Tbl_Solicitantes s ON s.sol_id=sa.solapoyo_solicitanteid'
      +where+' AND sa.solapoyo_id=:sid',{**params,'sid':sid})
    if not rows:
        raise HTTPException(404,'Solicitud no encontrada.')
    return rows[0]


@router.post('/solicitudes',status_code=201)
def create_request(data:NewRequest,user=Depends(current_user),db:Session=Depends(get_db)):
    return save_ssnl_request(data,user,db)


@router.get('/exportar/{format}')
def export(format:Literal['xlsx','pdf'],selected=Depends(svc.filters),user=Depends(current_user),db:Session=Depends(get_db),
    chart_apoyos:Literal['donut','bars','stacked','treemap']='donut',
    chart_grupos:Literal['donut','bars','stacked','treemap']='donut'):
    # Only aggregate queries: no request rows or personal fields enter the renderer.
    summary = svc.dashboard(db, user, selected, full_history=True)
    report = build_report(summary, user, selected, catalogs(user, db))
    report['chart_types'] = {'apoyos': chart_apoyos, 'grupos': chart_grupos}
    content = render_xlsx(report) if format == 'xlsx' else render_pdf(report)
    mime = ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            if format == 'xlsx' else 'application/pdf')
    return Response(content, media_type=mime, headers={
        'Content-Disposition': f'attachment; filename="SIESAS-ejecutivo.{format}"',
        'Cache-Control': 'no-store',
    })
