"""Registro Ejecutivo: alta de solicitudes con folio, origen ejecutivo y estatus inicial de
SSNL, más las búsquedas que necesita el formulario (personas, colonias y municipios).

Mismas rutas, parámetros y respuestas que app/routers/executive.py.
"""
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from sgsc_common import consulta as svc
from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_registro.registration import NewRequest, create_request as save_ssnl_request

router=APIRouter(prefix='/ejecutivo',tags=['Registro Ejecutivo'])


@router.get('/municipios-nacimiento')
def birth_municipalities(entidad_id:int=Query(gt=0),user=Depends(current_user),db:Session=Depends(get_db)):
    return {'items':svc.query_rows(db,"SELECT id,nom_mun AS nombre FROM INEGI_Cat_Municipios WHERE entidad_id=:eid AND cve_mun<>'999' ORDER BY nom_mun",{'eid':entidad_id})}


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
    # Every word must appear in the name, in any order ("martinez maria");
    # the collation ignores accents and capitals. People with the same name
    # are told apart by CURP or phone, birth date, municipality and requests.
    if tipo=='beneficiario':
        found,params=svc.matches([svc.BENEFICIARY],svc.search_terms(q),'p')
        sql=f"""SELECT b.ben_id AS id, CONCAT(b.ben_gen_name,' ',b.ben_gen_lastname,' · #',b.ben_id) AS nombre,
          NULLIF(b.ben_gen_curp,'') AS curp, b.ben_gen_birthdate AS fecha_nacimiento, m.nom_mun AS municipio,
          (SELECT COUNT(*) FROM Tbl_SolicitudesApoyo sa WHERE sa.solapoyo_beneficiarioid=b.ben_id) AS solicitudes
          FROM Tbl_Beneficiarios b JOIN INEGI_Cat_Municipios m ON m.id=b.ben_dom_municipio AND m.entidad_id=b.ben_dom_entidad
          WHERE b.is_active=1 AND b.ben_dom_entidad=:eid
          AND ((TRUE{found}) OR b.ben_gen_curp=:exact)
          ORDER BY b.ben_gen_name,b.ben_id LIMIT 30"""
    else:
        found,params=svc.matches([svc.APPLICANT],svc.search_terms(q),'p')
        sql=f"""SELECT s.sol_id AS id, CONCAT(s.sol_nombres,' ',s.sol_apellidos,' · #',s.sol_id) AS nombre,
          NULLIF(s.sol_telefono,'') AS telefono, s.sol_fecha_nacimiento AS fecha_nacimiento, m.nom_mun AS municipio,
          (SELECT COUNT(*) FROM Tbl_SolicitudesApoyo sa WHERE sa.solapoyo_solicitanteid=s.sol_id) AS solicitudes
          FROM Tbl_Solicitantes s JOIN INEGI_Cat_Municipios m ON m.id=s.sol_municipioid AND m.entidad_id=s.sol_estadoid
          WHERE s.is_active=1 AND s.sol_estadoid=:eid
          AND ((TRUE{found}) OR s.sol_telefono=:exact) ORDER BY s.sol_nombres,s.sol_id LIMIT 30"""
    return {'items':svc.query_rows(db,sql,{**params,'eid':user['entidad_id'],'exact':q.strip()})}


@router.post('/solicitudes',status_code=201)
def create_request(data:NewRequest,user=Depends(current_user),db:Session=Depends(get_db)):
    return save_ssnl_request(data,user,db)
