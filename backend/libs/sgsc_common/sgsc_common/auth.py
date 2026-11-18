"""Validación de la sesión del Ejecutivo en los microservicios (solo lectura).

Copia literal de la validación de app/security.py: el mismo token opaco, guardado como
hash SHA-256 en ejecutivo_token, y las mismas condiciones de cuenta activa, rol Ejecutivo
y entidad asignada. Emitir, revocar o limitar intentos sigue siendo tarea del núcleo
(/auth/*); aquí solo se consulta.
"""
import hashlib
from datetime import datetime, timezone

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import text
from sqlalchemy.orm import Session

from sgsc_common.database import get_db

bearer = HTTPBearer(auto_error=False)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


USER_SQL = """SELECT u.us_id AS usuario_id, u.us_name AS nombres, u.us_lastname AS apellidos, u.us_email AS correo,
 a.entidad_id, e.nom_ent AS entidad, e.cve_ent AS clave_inegi, a.totp_secret, a.totp_last_step
 FROM Tbl_Users u JOIN ejecutivo_acceso a ON a.usuario_id=u.us_id
 JOIN INEGI_Cat_Entidades e ON e.id=a.entidad_id
 WHERE u.is_active=1 AND EXISTS (
 SELECT 1 FROM auth_assignment aa JOIN auth_item ai ON ai.name=aa.item_name
 WHERE aa.user_id=CAST(u.us_id AS CHAR) AND ai.name='Ejecutivo' AND ai.type=1)"""


def authorized_user(db, uid):
    return db.execute(text(USER_SQL + ' AND u.us_id=:uid'), {'uid': uid}).mappings().first()


def current_user(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    if not credentials:
        raise HTTPException(401, 'Inicia sesión para continuar.')
    token = db.execute(text('''SELECT usuario_id FROM ejecutivo_token
      WHERE token_hash=:token AND tipo='session' AND usado IS NULL AND expira>:now'''),
      {'token': digest(credentials.credentials), 'now': now()}).scalar()
    user = authorized_user(db, token) if token else None
    if not user:
        raise HTTPException(401, 'Tu sesión venció. Inicia sesión nuevamente.')
    return dict(user)
