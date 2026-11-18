"""Comparación de periodos. Copia de backend/tests/test_comparison.py."""
from datetime import date
import pytest
from fastapi import HTTPException
from sgsc_indicadores import service as svc

FEB_24, FEB_25 = (date(2024,2,1),date(2024,2,29)), (date(2025,2,1),date(2025,2,28))


def row(*periods):
    """One aggregate row as MySQL returns it, from (total, activas, resueltas) per period."""
    return {f'{key}_{i}': value for i, values in enumerate(periods)
            for key, value in zip(['total','activas','resueltas'], values)}


def test_comparison_zero_baseline_and_same_scope(monkeypatch):
    calls = []
    def query(db, sql, params):
        calls.append((sql, params))
        assert 'm.entidad_id=:entidad_id' in sql
        return [row((0,0,0),(4,1,3))]
    monkeypatch.setattr(svc,'query_rows',query)
    result = svc.compare_periods(None,{'entidad_id':1},{'municipio_id':2,'fecha_inicio':date(2020,1,1)},[FEB_24,FEB_25])
    first, second = result['periodos']
    assert first['variacion'] is None and first['total'] == 0
    assert second['variacion']['total']=={'diferencia':4,'porcentaje':None}
    # One query; the general date range is replaced by the chosen periods.
    (sql, params), = calls
    assert params['municipio_id']==2 and 'fecha_inicio' not in params
    assert (params['pi0'],params['pf1'])==(date(2024,2,1),date(2025,2,28))


def test_each_period_compares_with_the_one_before(monkeypatch):
    monkeypatch.setattr(svc,'query_rows',lambda *args:[row((10,5,5),(0,0,0),(5,2,3))])
    d=(date(2025,1,1),date(2025,1,31))
    periods = svc.compare_periods(None,{'entidad_id':1},{},[d,d,d])['periodos']
    assert [p['total'] for p in periods]==[10,0,5]
    assert periods[1]['variacion']['total']=={'diferencia':-10,'porcentaje':-100.0}
    # A period without records has no baseline for a percentage.
    assert periods[2]['variacion']['total']=={'diferencia':5,'porcentaje':None}


@pytest.mark.parametrize('a,b,expected',[(10,5,-50.0),(5,10,100.0),(0,0,0),(3,3,0)])
def test_variation(a,b,expected):
    assert svc.variation(a,b)['porcentaje']==expected


@pytest.mark.parametrize('periods',[[FEB_24],[FEB_24]*13,[(date(2025,2,1),date(2025,1,1)),FEB_24]])
def test_invalid_periods(periods):
    with pytest.raises(HTTPException) as err:
        svc.compare_periods(None,{},{},periods)
    assert err.value.status_code==422
