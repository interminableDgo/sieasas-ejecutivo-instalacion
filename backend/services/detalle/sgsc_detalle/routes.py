"""Detalle de Indicadores: solicitudes relacionadas, con los mismos filtros del tablero,
y detalle de una solicitud dentro de la entidad autorizada.

Mismas rutas, parámetros y respuestas que app/routers/executive.py.
"""
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_detalle import service as svc

router=APIRouter(prefix='/ejecutivo',tags=['Detalle de Indicadores'])


@router.get('/solicitudes')
def requests(selected=Depends(svc.filters),page:int=Query(0,ge=0),q:str|None=Query(None,max_length=80),
    orden:Literal[tuple(svc.SORT_COLUMNS)]='fecha',direccion:Literal['asc','desc']='desc',
    user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.list_rows(db,user,selected,10,page*10,q,orden,direccion=='asc')


# Declared before /solicitudes/{sid} so "sugerencias" is not read as an id.
@router.get('/solicitudes/sugerencias')
def request_suggestions(q:str=Query(...,min_length=1,max_length=80),selected=Depends(svc.filters),
    user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.suggestions(db,user,selected,q)


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
