"""Indicadores y Filtros: consultar indicadores, filtrar y recalcular resultados.

Mismas rutas, parámetros y respuestas que app/routers/executive.py.
"""
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_indicadores import service as svc

router=APIRouter(prefix='/ejecutivo',tags=['Indicadores y Filtros'])


@router.get('/catalogos')
def catalogs(user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.catalogs(user,db)


@router.get('/dashboard')
def dashboard(selected=Depends(svc.filters),user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.dashboard(db,user,selected)


@router.get('/comparacion')
def comparison(inicio:list[date]=Query(...),fin:list[date]=Query(...),
    selected=Depends(svc.filters),user=Depends(current_user),db:Session=Depends(get_db)):
    # Repeated pairs, in order: ?inicio=2026-01-01&fin=2026-01-31&inicio=2026-02-01&fin=2026-02-28
    if len(inicio)!=len(fin):
        raise HTTPException(422,'Cada periodo necesita fecha inicial y final.')
    return svc.compare_periods(db,user,selected,list(zip(inicio,fin)))
