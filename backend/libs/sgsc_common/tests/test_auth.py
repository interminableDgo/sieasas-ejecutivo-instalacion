"""Validación de sesión de solo lectura: mismo token opaco y mismas reglas que el núcleo."""
from unittest.mock import Mock

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from sgsc_common.auth import USER_SQL, current_user, digest


def credentials(token='token-de-prueba'):
    return HTTPAuthorizationCredentials(scheme='Bearer', credentials=token)


def test_missing_token_is_401_without_queries():
    db = Mock()
    with pytest.raises(HTTPException) as caught:
        current_user(None, db)
    assert caught.value.status_code == 401
    db.execute.assert_not_called()


def test_unknown_or_expired_token_is_401():
    db = Mock()
    db.execute.return_value.scalar.return_value = None
    with pytest.raises(HTTPException) as caught:
        current_user(credentials(), db)
    assert caught.value.status_code == 401
    sql, params = db.execute.call_args.args
    assert "tipo='session'" in str(sql) and 'usado IS NULL' in str(sql) and 'expira>:now' in str(sql)
    assert params['token'] == digest('token-de-prueba') != 'token-de-prueba'


def test_valid_session_returns_the_authorized_user():
    db = Mock()
    session = Mock(scalar=Mock(return_value=42))
    user = Mock()
    user.mappings.return_value.first.return_value = {'usuario_id': 42, 'entidad_id': 19}
    db.execute.side_effect = [session, user]
    assert current_user(credentials(), db) == {'usuario_id': 42, 'entidad_id': 19}
    sql, params = db.execute.call_args_list[1].args
    assert str(sql).startswith(USER_SQL) and params == {'uid': 42}


def test_session_of_a_user_without_executive_access_is_401():
    db = Mock()
    session = Mock(scalar=Mock(return_value=42))
    user = Mock()
    user.mappings.return_value.first.return_value = None
    db.execute.side_effect = [session, user]
    with pytest.raises(HTTPException) as caught:
        current_user(credentials(), db)
    assert caught.value.status_code == 401


def test_user_sql_requires_active_account_executive_role_and_entity():
    assert 'u.is_active=1' in USER_SQL
    assert "ai.name='Ejecutivo'" in USER_SQL
    assert 'JOIN ejecutivo_acceso a' in USER_SQL and 'a.entidad_id' in USER_SQL
    assert 'INSERT' not in USER_SQL.upper() and 'UPDATE' not in USER_SQL.upper()
