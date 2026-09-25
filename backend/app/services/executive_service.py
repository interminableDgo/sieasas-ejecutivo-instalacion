"""Queries against the original SSNL tables; API aliases are presentation only."""
from datetime import date
from fastapi import HTTPException, Query
from sqlalchemy import text

JOINS = ''' FROM Tbl_SolicitudesApoyo sa
 JOIN Tbl_Beneficiarios b ON b.ben_id=sa.solapoyo_beneficiarioid
 JOIN INEGI_Cat_Municipios m ON m.id=b.ben_dom_municipio AND m.entidad_id=b.ben_dom_entidad
 JOIN Cat_TipoApoyo ta ON ta.id=sa.solapoyo_tipoapoyoid
 LEFT JOIN Cat_Dependencias d ON d.id=sa.solapoyo_enviadopor_dependenciaid
 LEFT JOIN Cat_GruposVulnerables g ON g.id=b.ben_misc_grupovulnerable_id
 JOIN Cat_StatusAtencion es ON es.id=sa.solapoyo_statusid'''
RESOLVED = "es.descripcion IN ('Resuelto','Resuelto con observación')"
ACTIVE = "es.descripcion NOT IN ('Resuelto','Resuelto con observación','Cerrado / Cancelado','No es competencia')"
FILTER_COLUMNS = {'municipio_id':'m.id', 'tipo_apoyo_id':'sa.solapoyo_tipoapoyoid',
 'dependencia_id':'sa.solapoyo_enviadopor_dependenciaid',
 'grupo_vulnerable_id':'b.ben_misc_grupovulnerable_id', 'estatus_id':'sa.solapoyo_statusid'}


MAX_VALUES_PER_FILTER = 100


def filters(municipio_id: list[int] | None = Query(None),
    tipo_apoyo_id: list[int] | None = Query(None), dependencia_id: list[int] | None = Query(None),
    grupo_vulnerable_id: list[int] | None = Query(None), estatus_id: list[int] | None = Query(None),
    fecha_inicio: date | None = None, fecha_fin: date | None = None,
    region_id: int | None = Query(None, gt=0)):
    """Each catalog filter accepts repeated values (?estatus_id=1&estatus_id=5):
    values of one filter are alternatives (OR), different filters combine (AND)."""
    # Called directly (not through FastAPI) the defaults are Query markers.
    if isinstance(region_id, int):
        raise HTTPException(422, 'SSNL no clasifica los municipios por región. Utiliza el filtro de municipio.')
    if isinstance(fecha_inicio, date) and isinstance(fecha_fin, date) and fecha_inicio > fecha_fin:
        raise HTTPException(422, 'La fecha inicial debe ser anterior a la final.')
    selected = {}
    for key, value in locals().items():
        if key in FILTER_COLUMNS and isinstance(value, list) and value:
            if len(value) > MAX_VALUES_PER_FILTER or any(v <= 0 for v in value):
                raise HTTPException(422, 'Filtro inválido.')
            unique = list(dict.fromkeys(value))
            selected[key] = unique[0] if len(unique) == 1 else unique
        elif key in ('fecha_inicio', 'fecha_fin') and isinstance(value, date):
            selected[key] = value
    return selected


def where_clause(user, selected):
    clauses = ['m.entidad_id=:entidad_id']
    params = {'entidad_id': user['entidad_id']}
    for key, column in FILTER_COLUMNS.items():
        if key not in selected:
            continue
        value = selected[key]
        if isinstance(value, (list, tuple)):
            names = [f'{key}_{i}' for i in range(len(value))]
            clauses.append(f"{column} IN ({','.join(':' + n for n in names)})")
            params.update(zip(names, value))
        else:
            clauses.append(f'{column}=:{key}')
            params[key] = value
    if selected.get('fecha_inicio'):
        clauses.append('sa.created>=:fecha_inicio')
        params['fecha_inicio'] = selected['fecha_inicio']
    if selected.get('fecha_fin'):
        clauses.append('sa.created<DATE_ADD(:fecha_fin, INTERVAL 1 DAY)')
        params['fecha_fin'] = selected['fecha_fin']
    return ' WHERE ' + ' AND '.join(clauses), params


def query_rows(db, sql, params):
    return [dict(r) for r in db.execute(text(sql), params).mappings()]


def groups(db, user, selected):
    where, params = where_clause(user, selected)
    result = {}
    for key, column, label in [
        ('municipios','m.id','m.nom_mun'), ('apoyos','ta.id','ta.descripcion'),
        ('dependencias','d.id','d.descripcion'), ('grupos','g.id','g.descripcion')]:
        result[key] = query_rows(db, f'''SELECT {column} AS id, COALESCE({label},'Sin información') AS nombre,
          COUNT(*) AS total {JOINS} {where} GROUP BY {column},{label} ORDER BY total DESC,nombre''', params)
    return result


def month_series(rows, today=None):
    today = today or date.today()
    start = today.year * 12 + today.month - 1 - 11
    indexed = {r['mes']: r for r in rows}
    result=[]
    for number in range(start, start+12):
        year, month = divmod(number, 12)
        key=f'{year:04d}-{month+1:02d}'
        result.append({'mes':key, 'recibidas':0, 'resueltas':0, **indexed.get(key,{})})
    return result


def dashboard(db, user, selected):
    where, params = where_clause(user, selected)
    totals = query_rows(db, f'''SELECT COUNT(*) AS total, COALESCE(SUM({RESOLVED}),0) AS resueltas,
      COALESCE(SUM({ACTIVE}),0) AS activas {JOINS} {where}''', params)[0]
    # Both series use registration cohorts, never an invented closure date.
    series=query_rows(db, f'''SELECT DATE_FORMAT(sa.created,'%Y-%m') AS mes,
      COUNT(*) AS recibidas, COALESCE(SUM({RESOLVED}),0) AS resueltas
      {JOINS} {where} GROUP BY mes ORDER BY mes''', params)
    return {**totals, **groups(db,user,selected), 'tendencia': month_series(series), 'datos_demo': 0}


def compare_periods(db, user, selected, a_inicio, a_fin, b_inicio, b_fin):
    if a_inicio > a_fin or b_inicio > b_fin:
        raise HTTPException(422, 'La fecha inicial debe ser anterior a la final.')
    periods = []
    for start, end in [(a_inicio, a_fin), (b_inicio, b_fin)]:
        where, params = where_clause(user, {**selected, 'fecha_inicio': start, 'fecha_fin': end})
        values = query_rows(db, f'''SELECT COUNT(*) AS total,
          COALESCE(SUM({ACTIVE}),0) AS activas,
          COALESCE(SUM({RESOLVED}),0) AS resueltas, 0 AS datos_demo '''+JOINS+where, params)[0]
        periods.append({'inicio': start, 'fin': end, **{k:int(v) for k,v in values.items()}})
    changes = {}
    for key in ['total', 'activas', 'resueltas']:
        a, b = periods[0][key], periods[1][key]
        changes[key] = {'diferencia': b-a, 'porcentaje': round((b-a)*100/a, 1) if a else (0 if b == 0 else None)}
    return {'a': periods[0], 'b': periods[1], 'variacion': changes}


ROW_SELECT = '''SELECT sa.solapoyo_id AS solicitud_id, CONCAT('Solicitud #',sa.solapoyo_id) AS folio,
 sa.created AS fecha_registro, m.nom_mun AS municipio, ta.descripcion AS tipo_apoyo,
 COALESCE(d.descripcion,'Sin dependencia remitente') AS dependencia,
 es.descripcion AS estatus, COALESCE(g.descripcion,'Sin información') AS grupo_vulnerable'''


def list_rows(db,user,selected,limit=10,offset=0):
    where, params=where_clause(user,selected)
    total=db.execute(text('SELECT COUNT(*) '+JOINS+where),params).scalar_one()
    rows=query_rows(db, ROW_SELECT+JOINS+where+' ORDER BY sa.created DESC, sa.solapoyo_id DESC LIMIT :limit OFFSET :offset',
      {**params,'limit':limit,'offset':offset})
    return {'total':total, 'items':rows}
