"""Búsqueda y orden de la tabla de solicitudes (sin base de datos)."""
from unittest.mock import Mock

from sgsc_detalle import service as svc


def test_search_scope_keeps_entity_filters_and_parameters():
    scope, params = svc.search_scope({'entidad_id': 19}, {'estatus_id': 1}, 'ana #14')
    assert 'm.entidad_id=:entidad_id' in scope and 'sa.solapoyo_statusid=:estatus_id' in scope
    assert 'LEFT JOIN Tbl_Solicitantes s' in scope
    assert params['entidad_id'] == 19 and params['q0'] == '%ana%' and params['q1_folio'] == 14
    assert 'ana' not in scope


def test_sorting_uses_only_fixed_columns_and_stable_ties():
    db = Mock()
    db.execute.return_value.scalar_one.return_value = 0
    db.execute.return_value.mappings.return_value = []
    svc.list_rows(db, {'entidad_id': 19}, {}, 10, 0, None, 'beneficiario', True)
    sql = str(db.execute.call_args_list[-1].args[0])
    assert f"ORDER BY {svc.SORT_COLUMNS['beneficiario']} ASC, sa.created DESC, sa.solapoyo_id DESC" in sql
    assert db.execute.call_args_list[-1].args[1]['limit'] == 10


def test_suggestions_without_words_do_not_query():
    db = Mock()
    assert svc.suggestions(db, {'entidad_id': 19}, {}, '   ') == {'total': 0, 'solicitudes': [], 'personas': []}
    db.execute.assert_not_called()
