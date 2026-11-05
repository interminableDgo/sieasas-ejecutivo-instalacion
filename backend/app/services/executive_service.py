"""Queries against the original SSNL tables; API aliases are presentation only."""
import re
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
# The rest of the total, so activas + resueltas + these always add up.
NOT_COMPETENT = "es.descripcion='No es competencia'"
CANCELLED = "es.descripcion='Cerrado / Cancelado'"
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


def month_series(rows, today=None, *, start_date=None, end_date=None):
    today = today or date.today()

    def month_number(value):
        return value.year * 12 + value.month - 1

    end = month_number(today)
    start = end - 11
    if start_date is not None or end_date is not None:
        # SQL has already applied the exact dates; only fill missing months here.
        data_months = [month_number(date.fromisoformat(r['mes'] + '-01')) for r in rows]
        end = month_number(end_date) if end_date else max(
            [end, *data_months, *([month_number(start_date)] if start_date else [])]
        )
        start = month_number(start_date) if start_date else min(data_months, default=end - 11)
    indexed = {r['mes']: r for r in rows}
    result=[]
    for number in range(start, end+1):
        year, month = divmod(number, 12)
        key=f'{year:04d}-{month+1:02d}'
        result.append({'mes':key, 'recibidas':0, 'resueltas':0, **indexed.get(key,{})})
    return result


def dashboard(db, user, selected, *, full_history=False):
    where, params = where_clause(user, selected)
    totals = query_rows(db, f'''SELECT COUNT(*) AS total, COALESCE(SUM({RESOLVED}),0) AS resueltas,
      COALESCE(SUM({ACTIVE}),0) AS activas, COALESCE(SUM({NOT_COMPETENT}),0) AS no_competencia,
      COALESCE(SUM({CANCELLED}),0) AS canceladas {JOINS} {where}''', params)[0]
    # Both series use registration cohorts, never an invented closure date.
    series=query_rows(db, f'''SELECT DATE_FORMAT(sa.created,'%Y-%m') AS mes,
      COUNT(*) AS recibidas, COALESCE(SUM({RESOLVED}),0) AS resueltas
      {JOINS} {where} GROUP BY mes ORDER BY mes''', params)
    start, end = selected.get('fecha_inicio'), selected.get('fecha_fin')
    if full_history and series:
        start = start or date.fromisoformat(series[0]['mes'] + '-01')
        end = end or date.fromisoformat(series[-1]['mes'] + '-01')
    return {**totals, **groups(db,user,selected), 'tendencia': month_series(
        series, start_date=start, end_date=end
    ), 'datos_demo': 0}


MAX_PERIODS = 12
PERIOD_KEYS = {'total': 'TRUE', 'activas': ACTIVE, 'resueltas': RESOLVED}


def variation(a, b):
    return {'diferencia': b-a, 'porcentaje': round((b-a)*100/a, 1) if a else (0 if b == 0 else None)}


def compare_periods(db, user, selected, periods):
    """Counts for 2 to 12 periods in a single query. Each period after the
    first carries its change against the one before it, in the order given."""
    if not 2 <= len(periods) <= MAX_PERIODS:
        raise HTTPException(422, f'Elige de 2 a {MAX_PERIODS} periodos.')
    if any(start > end for start, end in periods):
        raise HTTPException(422, 'La fecha inicial debe ser anterior a la final.')
    # The dates chosen here replace the general date range.
    scope = {k: v for k, v in selected.items() if k not in ('fecha_inicio', 'fecha_fin')}
    where, params = where_clause(user, scope)
    columns, ranges = [], []
    for i, (start, end) in enumerate(periods):
        params[f'pi{i}'], params[f'pf{i}'] = start, end
        inside = f'(sa.created>=:pi{i} AND sa.created<DATE_ADD(:pf{i}, INTERVAL 1 DAY))'
        ranges.append(inside)
        columns += [f'COALESCE(SUM({inside} AND {rule}),0) AS {key}_{i}' for key, rule in PERIOD_KEYS.items()]
    row = query_rows(db, 'SELECT ' + ', '.join(columns) + JOINS + where
                     + ' AND (' + ' OR '.join(ranges) + ')', params)[0]
    result = []
    for i, (start, end) in enumerate(periods):
        values = {key: int(row[f'{key}_{i}'] or 0) for key in PERIOD_KEYS}
        change = {key: variation(result[-1][key], values[key]) for key in PERIOD_KEYS} if result else None
        result.append({'inicio': start, 'fin': end, **values, 'variacion': change})
    return {'periodos': result}


ROW_SELECT = '''SELECT sa.solapoyo_id AS solicitud_id, CONCAT('Solicitud #',sa.solapoyo_id) AS folio,
 sa.created AS fecha_registro, m.nom_mun AS municipio, ta.descripcion AS tipo_apoyo,
 COALESCE(d.descripcion,'Sin dependencia remitente') AS dependencia,
 es.descripcion AS estatus, COALESCE(g.descripcion,'Sin información') AS grupo_vulnerable'''


# The table also shows who is involved, so a search by name has visible results.
PEOPLE_SELECT = ''', CONCAT_WS(' ',b.ben_gen_name,b.ben_gen_lastname) AS beneficiario,
 CONCAT_WS(' ',s.sol_nombres,s.sol_apellidos) AS solicitante'''
PEOPLE_JOIN = ' LEFT JOIN Tbl_Solicitantes s ON s.sol_id=sa.solapoyo_solicitanteid'
BENEFICIARY = "CONCAT_WS(' ',b.ben_gen_name,b.ben_gen_lastname)"
APPLICANT = "CONCAT_WS(' ',s.sol_nombres,s.sol_apellidos)"
# 05/10/2026, 5/10/2026 and 2026-10-05 all find the same registration date.
DATES = ["DATE_FORMAT(sa.created,'%d/%m/%Y')", "DATE_FORMAT(sa.created,'%e/%c/%Y')",
 "DATE_FORMAT(sa.created,'%Y-%m-%d')"]
MONTHS = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
 'septiembre','octubre','noviembre','diciembre']
MAX_SEARCH_TERMS = 6


def looks_like_date(term):
    """Only date-shaped words search the date, so a number such as 026 does
    not match every request registered in 2026."""
    return bool(re.fullmatch(r'[\d/-]+', term)) and ('/' in term or '-' in term or len(term) == 4)


def search_terms(q):
    return (q or '').split()[:MAX_SEARCH_TERMS]


def folio_number(term):
    """'14' or '#14' names Solicitud #14."""
    digits = term.removeprefix('#')
    return int(digits) if digits.isdigit() and len(digits) <= 9 else None


def matches(columns, terms, prefix, *, months=False, folio=False):
    """Every word must appear in one of the columns. Names use the
    utf8mb4_unicode_ci collation, so accents and capitals do not matter."""
    clauses, params = [], {}
    for i, term in enumerate(terms):
        name = f'{prefix}{i}'
        like = term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        params[name] = f'%{like}%'
        options = [f'{column} LIKE :{name}' for column in columns
                   if column not in DATES or looks_like_date(term)]
        if months and len(term) >= 3:
            plain = term.lower().translate(str.maketrans('áéíóú', 'aeiou'))
            for number, month in enumerate(MONTHS, 1):
                if month.startswith(plain):
                    options.append(f'MONTH(sa.created)={number}')
        if folio and folio_number(term) is not None:
            params[name + '_folio'] = folio_number(term)
            options.append(f'sa.solapoyo_id=:{name}_folio')
        clauses.append('(' + (' OR '.join(options) or 'FALSE') + ')')
    return ''.join(' AND ' + c for c in clauses), params


# Besides the people and the date, the type of support, the status and the
# folio tell apart two requests of the same person ("jorge vacuna", "jorge 14").
REQUEST_SEARCH = [BENEFICIARY, APPLICANT, *DATES, 'ta.descripcion', 'es.descripcion']


def search_scope(user, selected, q):
    where, params = where_clause(user, selected)
    search, extra = matches(REQUEST_SEARCH, search_terms(q), 'q', months=True, folio=True)
    return JOINS + PEOPLE_JOIN + where + search, {**params, **extra}


def list_rows(db,user,selected,limit=10,offset=0,q=None):
    scope, params=search_scope(user,selected,q)
    total=db.execute(text('SELECT COUNT(*) '+scope),params).scalar_one()
    rows=query_rows(db, ROW_SELECT+PEOPLE_SELECT+scope
      +' ORDER BY sa.created DESC, sa.solapoyo_id DESC LIMIT :limit OFFSET :offset',
      {**params,'limit':limit,'offset':offset})
    return {'total':total, 'items':rows}


def suggestions(db,user,selected,q,limit=5,people_limit=3):
    """What the search box offers while typing: the most recent matching
    requests (so one can be opened directly), the people involved with how
    many requests each has, and the total, never a long list."""
    terms = search_terms(q)
    if not terms:
        return {'total': 0, 'solicitudes': [], 'personas': []}
    scope, params = search_scope(user, selected, q)
    total = db.execute(text('SELECT COUNT(*) ' + scope), params).scalar_one()
    requests = query_rows(db, ROW_SELECT + PEOPLE_SELECT + scope
      + ' ORDER BY sa.created DESC, sa.solapoyo_id DESC LIMIT :limit', {**params, 'limit': limit})
    base_where, base_params = where_clause(user, selected)
    people, seen = [], set()
    for kind, column in [('Beneficiario', BENEFICIARY), ('Solicitante', APPLICANT)]:
        # Only people whose name contains at least one of the typed words.
        extra = {f'n{i}': params[f'q{i}'] for i in range(len(terms))}
        any_name = ' OR '.join(f'{column} LIKE :n{i}' for i in range(len(terms)))
        for row in query_rows(db, f"SELECT {column} AS nombre, '{kind}' AS tipo {scope} AND ({any_name})"
            f' GROUP BY {column} ORDER BY MAX(sa.created) DESC LIMIT {people_limit}', {**params, **extra}):
            if row['nombre'] in seen:
                continue
            seen.add(row['nombre'])
            # All requests of the person within the filters, not only the matching ones.
            row['total'] = db.execute(text(f'SELECT COUNT(*) {JOINS}{PEOPLE_JOIN}{base_where} AND {column}=:person'),
              {**base_params, 'person': row['nombre']}).scalar_one()
            people.append(row)
    return {'total': total, 'solicitudes': requests, 'personas': people[:people_limit]}
