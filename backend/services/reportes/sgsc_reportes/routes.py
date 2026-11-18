"""Reportes y Exportación: información filtrada en Excel o PDF, solo con agregados.

Calcula los agregados con el mismo contrato de consulta que Indicadores (sgsc_common),
sin llamarlo: la exportación sigue disponible aunque Indicadores esté detenido.
Mismas rutas, parámetros y respuestas que app/routers/executive.py.
"""
from typing import Literal

from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from sgsc_common import consulta as svc
from sgsc_common.auth import current_user
from sgsc_common.database import get_db
from sgsc_reportes.report import build_report, render_pdf, render_xlsx

router=APIRouter(prefix='/ejecutivo',tags=['Reportes y Exportación'])


def catalogs(user,db):
    # Etiquetas de los filtros aplicados que se imprimen en el reporte.
    return svc.catalogs(user,db)


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
