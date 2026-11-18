"""Contrato de filtros y agregados. Casos tomados de backend/tests (test_executive,
test_sprint1 y test_export), sin base de datos."""
from datetime import date

import pytest
from fastapi import HTTPException

from sgsc_common import consulta as svc
from sgsc_common.consulta import DATES, filters, looks_like_date, matches, month_series, where_clause


def test_months_zero_fill_and_year_boundary():
    result = month_series([{'mes': '2026-01', 'recibidas': 2, 'resueltas': 1}], date(2026, 2, 1))
    assert len(result) == 12
    assert result[0]['mes'] == '2025-03'
    assert result[-2]['recibidas'] == 2
    assert result[-1]['recibidas'] == 0


def test_scope_always_applied_and_parameterized():
    where, params = where_clause({'entidad_id': 7}, {'municipio_id': 12, 'dependencia_id': 3})
    assert 'm.entidad_id=:entidad_id' in where
    assert params == {'entidad_id': 7, 'municipio_id': 12, 'dependencia_id': 3}


def test_multiple_values_are_alternatives_within_a_filter():
    where, params = where_clause({'entidad_id': 7}, {'municipio_id': [12, 15], 'estatus_id': 1})
    assert 'm.id IN (:municipio_id_0,:municipio_id_1)' in where
    assert 'sa.solapoyo_statusid=:estatus_id' in where
    assert 'm.entidad_id=:entidad_id' in where
    assert params == {'entidad_id': 7, 'municipio_id_0': 12, 'municipio_id_1': 15, 'estatus_id': 1}


def test_filters_accept_repeated_params_and_reject_invalid():
    assert filters(municipio_id=[3, 3], estatus_id=[1, 5]) == {'municipio_id': 3, 'estatus_id': [1, 5]}
    assert filters() == {}
    with pytest.raises(HTTPException):
        filters(municipio_id=[0])
    with pytest.raises(HTTPException):
        filters(tipo_apoyo_id=list(range(1, 102)))
    with pytest.raises(HTTPException) as caught:
        filters(region_id=1)
    assert caught.value.status_code == 422


def test_search_words_are_parameterized_and_dates_need_a_date_shape():
    sql, params = matches(['name'], ['50%_off'], 'q')
    assert params == {'q0': '%50\\%\\_off%'} and '50' not in sql
    assert looks_like_date('29/02/2024') and looks_like_date('2024-02') and looks_like_date('2024')
    assert not looks_like_date('026') and not looks_like_date('maria')
    sql, _ = matches(['name', *DATES], ['026'], 'q')
    assert 'DATE_FORMAT' not in sql
    sql, _ = matches(['name'], ['oct'], 'q', months=True)
    assert 'MONTH(sa.created)=10' in sql
    sql, params = matches(['name'], ['#14'], 'q', folio=True)
    assert 'sa.solapoyo_id=:q0_folio' in sql and params['q0_folio'] == 14
    assert 'solapoyo_id' not in matches(['name'], ['jorge'], 'q', folio=True)[0]


def test_inclusive_end_date_and_invalid_period():
    selected = dict(fecha_inicio=date(2026, 1, 1), fecha_fin=date(2026, 1, 31))
    clause, params = where_clause({'entidad_id': 19}, selected)
    assert 'sa.created>=:fecha_inicio' in clause
    assert 'sa.created<DATE_ADD(:fecha_fin, INTERVAL 1 DAY)' in clause
    assert params == {'entidad_id': 19, **selected}
    with pytest.raises(HTTPException) as caught:
        filters(fecha_inicio=date(2026, 2, 1), fecha_fin=date(2026, 1, 1))
    assert caught.value.status_code == 422


def test_historical_period_keeps_trend_data(monkeypatch):
    replies = iter([
        [{'total': 2, 'activas': 1, 'resueltas': 1}],
        [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1}],
        [{'id': 1, 'nombre': 'Municipio ficticio', 'total': 2}],
        [{'id': 1, 'nombre': 'Apoyo ficticio', 'total': 2}],
        [{'id': 1, 'nombre': 'Remitente ficticio', 'total': 2}],
        [{'id': 1, 'nombre': 'Grupo ficticio', 'total': 2}],
    ])
    monkeypatch.setattr(svc, 'query_rows', lambda *a: next(replies))
    result = svc.dashboard(None, {'entidad_id': 19}, {'fecha_inicio': date(2020, 1, 1), 'fecha_fin': date(2020, 1, 31)})
    assert result['total'] == 2
    assert result['tendencia'] == [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1}]


@pytest.mark.parametrize('start,end,months', [
    (date(2019, 12, 15), date(2020, 2, 5), ['2019-12', '2020-01', '2020-02']),
    (date(2020, 1, 1), date(2021, 1, 31), [f'2020-{m:02d}' for m in range(1, 13)] + ['2021-01']),
    (None, date(2020, 3, 31), ['2020-01', '2020-02', '2020-03']),
    (date(2020, 1, 1), None, ['2020-01', '2020-02', '2020-03']),
])
def test_trend_period_bounds_and_zero_fill(start, end, months):
    rows = [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1}]
    result = month_series(rows, today=date(2020, 3, 15), start_date=start, end_date=end)
    assert [r['mes'] for r in result] == months
    assert sum(r['recibidas'] for r in result) == 2


@pytest.mark.parametrize('with_end', [True, False])
def test_full_history_scope_and_final_day(monkeypatch, with_end):
    calls = []

    def query(db, sql, params):
        calls.append((sql, params))
        if 'DATE_FORMAT' in sql:
            return [{'mes': '2020-01', 'recibidas': 2, 'resueltas': 1},
                    {'mes': '2020-03', 'recibidas': 3, 'resueltas': 0}]
        if 'GROUP BY' in sql:
            return [{'id': 1, 'nombre': 'Prueba', 'total': 5}]
        return [{'total': 5, 'activas': 4, 'resueltas': 1}]
    monkeypatch.setattr(svc, 'query_rows', query)
    selected = {'municipio_id': [3, 4]}
    if with_end:
        selected['fecha_fin'] = date(2020, 3, 31)
    result = svc.dashboard(None, {'entidad_id': 19}, selected, full_history=True)
    assert [r['mes'] for r in result['tendencia']] == ['2020-01', '2020-02', '2020-03']
    for sql, params in calls:
        assert 'm.entidad_id=:entidad_id' in sql
        assert 'ben_gen_name' not in sql and 'solapoyo_id AS' not in sql


def test_catalogs_scope_municipalities_to_the_user_entity(monkeypatch):
    calls = []
    monkeypatch.setattr(svc, 'query_rows', lambda db, sql, params: calls.append((sql, params)) or [])
    result = svc.catalogs({'entidad_id': 19}, None)
    assert set(result) == {*svc.CATALOGS, 'municipios', 'entidades'}
    municipios = next(params for sql, params in calls if 'INEGI_Cat_Municipios' in sql)
    assert municipios == {'eid': 19}
