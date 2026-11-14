"""API del módulo Ciudadano: cuenta propia, perfil y solicitudes de esa cuenta."""
import hmac
import json
import logging
import secrets
from datetime import timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import SessionLocal, get_db
from app.security import bearer, digest, hasher, limit_request, now, verify_password
from app.services import ciudadano_service as svc
from app.services.auth_service import enviar, mensaje_codigo_ciudadano, smtp_configurado

router = APIRouter(prefix='/ciudadano', tags=['Ciudadano'])
DIAS_SESION = 30
MINUTOS_CODIGO = 15
INTENTOS_CODIGO = 5
GENERICO = {'message': 'Si el correo corresponde a una cuenta, te enviamos un código para recuperar el acceso.'}


class Credenciales(BaseModel):
    correo: EmailStr = Field(max_length=180)
    contrasena: str = Field(min_length=1, max_length=128)


class Registro(Credenciales):
    contrasena: str = Field(min_length=15, max_length=128)


class Correo(BaseModel):
    correo: EmailStr = Field(max_length=180)


class Restablecer(Correo):
    codigo: str = Field(pattern=r'^\d{6}$')
    contrasena: str = Field(min_length=15, max_length=128)


def hash_codigo(cuenta_id, codigo):
    return digest(f'{cuenta_id}:{codigo}')


def emitir_sesion(db, cuenta_id):
    token = secrets.token_urlsafe(32)
    db.execute(text('INSERT INTO ciudadano_sesion (token_hash,cuenta_id,expira) VALUES (:t,:c,:e)'),
               {'t': digest(token), 'c': cuenta_id, 'e': now() + timedelta(days=DIAS_SESION)})
    return token


def cuenta_actual(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    if not credentials:
        raise HTTPException(401, 'Inicia sesión para continuar.')
    cuenta = db.execute(text('''SELECT c.id,c.correo FROM ciudadano_sesion s JOIN ciudadano_cuenta c ON c.id=s.cuenta_id
      WHERE s.token_hash=:t AND s.expira>:now'''), {'t': digest(credentials.credentials), 'now': now()}).mappings().first()
    if not cuenta:
        raise HTTPException(401, 'Tu sesión venció. Inicia sesión nuevamente.')
    return dict(cuenta)


def normalizar(correo):
    return str(correo).strip().lower()


@router.post('/registro', status_code=201)
def registro(data: Registro, request: Request, db: Session = Depends(get_db)):
    correo = normalizar(data.correo)
    limit_request(db, request, 'ciudadano-registro', correo)
    perfil = svc.Perfil(correo=correo).model_dump(mode='json')
    try:
        cuenta_id = db.execute(text('INSERT INTO ciudadano_cuenta (correo,password_hash,perfil) VALUES (:c,:p,:perfil)'),
                               {'c': correo, 'p': hasher.hash(data.contrasena),
                                'perfil': json.dumps(perfil, ensure_ascii=False)}).lastrowid
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Ya existe una cuenta con ese correo. Inicia sesión.')
    token = emitir_sesion(db, cuenta_id)
    db.commit()
    return {'token': token, 'correo': correo}


@router.post('/login')
def login(data: Credenciales, request: Request, db: Session = Depends(get_db)):
    correo = normalizar(data.correo)
    limit_request(db, request, 'ciudadano-login', correo)
    cuenta = db.execute(text('SELECT id,password_hash FROM ciudadano_cuenta WHERE correo=:c'), {'c': correo}).mappings().first()
    # Se verifica siempre una contraseña para no revelar, por el tiempo de respuesta, si la cuenta existe.
    if not verify_password(cuenta['password_hash'] if cuenta else None, data.contrasena) or not cuenta:
        raise HTTPException(401, 'Correo o contraseña incorrectos.')
    token = emitir_sesion(db, cuenta['id'])
    db.execute(text('DELETE FROM ciudadano_sesion WHERE cuenta_id=:c AND expira<:now'), {'c': cuenta['id'], 'now': now()})
    db.commit()
    return {'token': token, 'correo': correo}


@router.post('/logout', status_code=204)
def logout(credentials: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)):
    if credentials:
        db.execute(text('DELETE FROM ciudadano_sesion WHERE token_hash=:t'), {'t': digest(credentials.credentials)})
        db.commit()


def enviar_codigo(correo):
    """Genera y envía el código después de responder, para no revelar si la cuenta existe."""
    with SessionLocal() as db:
        cuenta_id = db.execute(text('SELECT id FROM ciudadano_cuenta WHERE correo=:c'), {'c': correo}).scalar()
        if not cuenta_id:
            return
        codigo = f'{secrets.randbelow(10**6):06d}'
        db.execute(text('''INSERT INTO ciudadano_recuperacion (cuenta_id,codigo_hash,expira,intentos)
          VALUES (:c,:h,:e,0) ON DUPLICATE KEY UPDATE codigo_hash=:h, expira=:e, intentos=0'''),
                   {'c': cuenta_id, 'h': hash_codigo(cuenta_id, codigo), 'e': now() + timedelta(minutes=MINUTOS_CODIGO)})
        try:
            enviar(mensaje_codigo_ciudadano(correo, codigo, MINUTOS_CODIGO))
            db.commit()
        except Exception:
            db.rollback()
            logging.getLogger(__name__).error('No se pudo entregar un código de recuperación del Ciudadano; revisar SMTP.')


@router.post('/recuperar', status_code=202)
def recuperar(data: Correo, request: Request, tasks: BackgroundTasks, db: Session = Depends(get_db)):
    correo = normalizar(data.correo)
    limit_request(db, request, 'ciudadano-recuperar', correo)
    if not smtp_configurado():
        raise HTTPException(503, 'El servicio de recuperación por correo no está disponible.')
    # Misma respuesta exista o no la cuenta.
    tasks.add_task(enviar_codigo, correo)
    return GENERICO


@router.post('/restablecer')
def restablecer(data: Restablecer, request: Request, db: Session = Depends(get_db)):
    correo = normalizar(data.correo)
    limit_request(db, request, 'ciudadano-restablecer', correo)
    invalido = HTTPException(400, 'El código no es correcto o ya venció. Solicita uno nuevo.')
    fila = db.execute(text('''SELECT r.cuenta_id,r.codigo_hash,r.expira,r.intentos FROM ciudadano_recuperacion r
      JOIN ciudadano_cuenta c ON c.id=r.cuenta_id WHERE c.correo=:c FOR UPDATE'''), {'c': correo}).mappings().first()
    if not fila or fila['expira'] <= now() or fila['intentos'] >= INTENTOS_CODIGO:
        db.rollback()
        raise invalido
    if not hmac.compare_digest(fila['codigo_hash'], hash_codigo(fila['cuenta_id'], data.codigo)):
        db.execute(text('UPDATE ciudadano_recuperacion SET intentos=intentos+1 WHERE cuenta_id=:c'), {'c': fila['cuenta_id']})
        db.commit()
        raise invalido
    db.execute(text('UPDATE ciudadano_cuenta SET password_hash=:p WHERE id=:c'),
               {'p': hasher.hash(data.contrasena), 'c': fila['cuenta_id']})
    db.execute(text('DELETE FROM ciudadano_recuperacion WHERE cuenta_id=:c'), {'c': fila['cuenta_id']})
    # Cualquier sesión abierta con la contraseña anterior se cierra.
    db.execute(text('DELETE FROM ciudadano_sesion WHERE cuenta_id=:c'), {'c': fila['cuenta_id']})
    token = emitir_sesion(db, fila['cuenta_id'])
    db.commit()
    return {'token': token, 'correo': correo}


@router.get('/perfil')
def leer_perfil(cuenta=Depends(cuenta_actual), db: Session = Depends(get_db)):
    return svc.perfil_de(db, cuenta['id']).model_dump(mode='json')


@router.put('/perfil')
def guardar_perfil(perfil: svc.Perfil, cuenta=Depends(cuenta_actual), db: Session = Depends(get_db)):
    db.execute(text('UPDATE ciudadano_cuenta SET perfil=:p WHERE id=:id'),
               {'p': json.dumps(perfil.model_dump(mode='json'), ensure_ascii=False), 'id': cuenta['id']})
    svc.actualizar_contacto(db, cuenta['id'], perfil)
    db.commit()
    return perfil.model_dump(mode='json')


@router.get('/solicitudes')
def mis_solicitudes(cuenta=Depends(cuenta_actual), db: Session = Depends(get_db)):
    return {'items': svc.listar(db, cuenta['id'])}


@router.post('/solicitudes', status_code=201)
def nueva_solicitud(data: svc.NuevaSolicitud, cuenta=Depends(cuenta_actual), db: Session = Depends(get_db)):
    try:
        solicitud = svc.crear(db, cuenta['id'], data)
        db.commit()
        return solicitud
    except IntegrityError:
        db.rollback()
        previa = db.execute(text('SELECT solicitud_id FROM ciudadano_solicitud WHERE cuenta_id=:c AND idempotencia=:k'),
                            {'c': cuenta['id'], 'k': str(data.idempotencia)}).scalar()
        if previa:
            return svc.una(db, previa)
        raise HTTPException(409, 'No se pudo guardar la solicitud. Intenta nuevamente.')
    except HTTPException:
        db.rollback()
        raise
