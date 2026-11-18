"""Comparación de periodos del tablero (copia literal de executive_service.py)."""
from fastapi import HTTPException

from sgsc_common.consulta import (  # noqa: F401  (reexportados para las rutas)
    ACTIVE, JOINS, RESOLVED, catalogs, dashboard, filters, query_rows, where_clause,
)


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
