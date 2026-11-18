"""Solicitudes que conforman un indicador: lista, sugerencias y detalle
(copia literal de executive_service.py)."""
from sqlalchemy import text

from sgsc_common.consulta import (  # noqa: F401  (reexportados para las rutas)
    APPLICANT, BENEFICIARY, DATES, JOINS, filters, matches, query_rows, search_terms, where_clause,
)


ROW_SELECT = '''SELECT sa.solapoyo_id AS solicitud_id, CONCAT('Solicitud #',sa.solapoyo_id) AS folio,
 sa.created AS fecha_registro, m.nom_mun AS municipio, ta.descripcion AS tipo_apoyo,
 COALESCE(d.descripcion,'Sin dependencia remitente') AS dependencia,
 es.descripcion AS estatus, COALESCE(g.descripcion,'Sin información') AS grupo_vulnerable'''


# The table also shows who is involved, so a search by name has visible results.
PEOPLE_SELECT = ''', CONCAT_WS(' ',b.ben_gen_name,b.ben_gen_lastname) AS beneficiario,
 CONCAT_WS(' ',s.sol_nombres,s.sol_apellidos) AS solicitante'''
PEOPLE_JOIN = ' LEFT JOIN Tbl_Solicitantes s ON s.sol_id=sa.solapoyo_solicitanteid'


# Besides the people and the date, the type of support, the status and the
# folio tell apart two requests of the same person ("jorge vacuna", "jorge 14").
REQUEST_SEARCH = [BENEFICIARY, APPLICANT, *DATES, 'ta.descripcion', 'es.descripcion']


def search_scope(user, selected, q):
    where, params = where_clause(user, selected)
    search, extra = matches(REQUEST_SEARCH, search_terms(q), 'q', months=True, folio=True)
    return JOINS + PEOPLE_JOIN + where + search, {**params, **extra}


# Columns the table can be sorted by. Only these fixed expressions reach SQL.
SORT_COLUMNS = {'estatus': 'es.descripcion', 'solicitud': 'sa.solapoyo_id', 'fecha': 'sa.created',
 'beneficiario': BENEFICIARY, 'solicitante': APPLICANT, 'municipio': 'm.nom_mun',
 'tipo_apoyo': 'ta.descripcion', 'remitente': "COALESCE(d.descripcion,'Sin dependencia remitente')"}


def list_rows(db,user,selected,limit=10,offset=0,q=None,sort='fecha',ascending=False):
    scope, params=search_scope(user,selected,q)
    total=db.execute(text('SELECT COUNT(*) '+scope),params).scalar_one()
    # The newest first breaks ties, so pages never repeat or skip a row.
    order=f"{SORT_COLUMNS[sort]} {'ASC' if ascending else 'DESC'}, sa.created DESC, sa.solapoyo_id DESC"
    rows=query_rows(db, ROW_SELECT+PEOPLE_SELECT+scope
      +f' ORDER BY {order} LIMIT :limit OFFSET :offset',
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
        # Every word must be in this person's name or in a detail of the same
        # request (type, status, date, folio), never in the other person's
        # name: "jorge serangue" offers Jorge Seranguelli, not Jorge Pérez.
        # At least one word must be in the name, so a date alone offers nobody.
        own, extra = matches([column, *DATES, 'ta.descripcion', 'es.descripcion'], terms, 'n', months=True, folio=True)
        any_name = ' OR '.join(f'{column} LIKE :n{i}' for i in range(len(terms)))
        for row in query_rows(db, f"SELECT {column} AS nombre, '{kind}' AS tipo {scope}{own} AND ({any_name})"
            f' GROUP BY {column} ORDER BY MAX(sa.created) DESC LIMIT {people_limit}', {**params, **extra}):
            if row['nombre'] in seen:
                continue
            seen.add(row['nombre'])
            # All requests of the person within the filters, not only the matching ones.
            row['total'] = db.execute(text(f'SELECT COUNT(*) {JOINS}{PEOPLE_JOIN}{base_where} AND {column}=:person'),
              {**base_params, 'person': row['nombre']}).scalar_one()
            people.append(row)
    return {'total': total, 'solicitudes': requests, 'personas': people[:people_limit]}
