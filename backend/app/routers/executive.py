import io
from datetime import date, datetime, timezone
from html import escape
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.security import current_user
from app.services import executive_service as svc
from app.services.ssnl_registration import NewRequest, create_request as save_ssnl_request

router=APIRouter(prefix='/ejecutivo',tags=['Ejecutivo'])


CATALOGS = {'apoyos':'Cat_TipoApoyo','dependencias':'Cat_Dependencias','grupos':'Cat_GruposVulnerables',
 'estatus':'Cat_StatusAtencion','canales':'Cat_CanalesRecepcion','origenes':'Cat_EnviadoPor',
 'unidades':'Cat_UnidadesTratantes','parentescos':'Cat_Parentescos','generos':'Cat_Generos',
 'seguridad_social':'Cat_SeguridadSocial','partidos':'Cat_PartidosPoliticos'}

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
def requests(selected=Depends(svc.filters),page:int=Query(0,ge=0),user=Depends(current_user),db:Session=Depends(get_db)):
    return svc.list_rows(db,user,selected,10,page*10)


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


EXPORT_FIELDS=['folio','municipio','tipo_apoyo','dependencia','estatus','grupo_vulnerable','fecha_registro']
EXPORT_HEADERS=['Solicitud','Municipio','Tipo de apoyo','Dependencia remitente','Estatus','Grupo vulnerable','Registro']


@router.get('/exportar/{format}')
def export(format:Literal['xlsx','pdf'],selected=Depends(svc.filters),user=Depends(current_user),db:Session=Depends(get_db)):
    result=svc.list_rows(db,user,selected,10001,0)
    if result['total']>10000:
        raise HTTPException(422,'El reporte supera 10,000 solicitudes. Aplica filtros para exportar.')
    rows=result['items']
    summary=svc.dashboard(db,user,selected)
    metadata=f"{user['entidad']} · {datetime.now(timezone.utc):%Y-%m-%d %H:%M} UTC · {result['total']} solicitudes"
    cats=catalogs(user,db)
    labels={'municipio_id':('Municipio','municipios'),
      'tipo_apoyo_id':('Apoyo','apoyos'),'dependencia_id':('Dependencia remitente','dependencias'),
      'grupo_vulnerable_id':('Grupo','grupos'),'estatus_id':('Estatus','estatus')}
    filter_parts=[]
    for key,value in selected.items():
        if key in labels:
            label,cat=labels[key]
            ids=value if isinstance(value,list) else [value]
            value=', '.join(next((r['nombre'] for r in cats[cat] if r['id']==i),str(i)) for i in ids)
        else:
            label=key.replace('_',' ').capitalize()
        filter_parts.append(f'{label}: {value}')
    filter_text='; '.join(filter_parts) or 'Sin filtros adicionales'
    stream=io.BytesIO()
    if format=='xlsx':
        book=Workbook()
        sheet=book.active
        sheet.title='Solicitudes'
        sheet.append(['SIESAS · Ejecutivo'])
        sheet.append([metadata])
        sheet.append([filter_text])
        sheet.append(EXPORT_HEADERS)
        for row in rows:
            sheet.append([str(row.get(k) or 'Sin información') for k in EXPORT_FIELDS])
        # Treat every cell as text, including strings beginning with '='.
        for line in sheet:
            for cell in line:
                cell.data_type='s'
        for cell in sheet[4]:
            cell.font=Font(color='FFFFFF',bold=True)
            cell.fill=PatternFill('solid',fgColor='1B2A33')
        sheet.freeze_panes='A5'
        sheet.auto_filter.ref=f'A4:G{max(4,sheet.max_row)}'
        for column in 'ABCDEFG':
            sheet.column_dimensions[column].width=30
        trend=book.create_sheet('Tendencia')
        trend.append(['Mes de registro','Registradas','Resueltas actualmente'])
        for item in summary['tendencia']:
            trend.append([item['mes'],item['recibidas'],item['resueltas']])
        book.save(stream)
        mime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    else:
        styles=getSampleStyleSheet()
        styles['BodyText'].fontSize=8
        document=SimpleDocTemplate(stream,pagesize=landscape(A4),leftMargin=24,rightMargin=24,topMargin=24,bottomMargin=24)
        content=[Paragraph('SIESAS · Ejecutivo',styles['Title']),Paragraph(escape(metadata),styles['BodyText']),
          Paragraph(escape(filter_text),styles['BodyText']),Spacer(1,14)]
        table_rows=[EXPORT_HEADERS]+[[Paragraph(escape(str(r.get(k) or 'Sin información')),styles['BodyText']) for k in EXPORT_FIELDS] for r in rows]
        table=Table(table_rows,colWidths=[120,95,105,125,75,90,180-96],repeatRows=1)
        table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#1B2A33')),
          ('TEXTCOLOR',(0,0),(-1,0),colors.white),('FONTSIZE',(0,0),(-1,-1),8),
          ('VALIGN',(0,0),(-1,-1),'TOP'),('BOTTOMPADDING',(0,0),(-1,-1),8),
          ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#F3F3F0')])]))
        content.append(table)
        document.build(content)
        mime='application/pdf'
    return Response(stream.getvalue(),media_type=mime,headers={'Content-Disposition':f'attachment; filename="SIESAS-ejecutivo.{format}"','Cache-Control':'no-store'})
