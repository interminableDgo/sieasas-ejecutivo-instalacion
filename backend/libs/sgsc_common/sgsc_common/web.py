"""Aplicación FastAPI base de cada microservicio del Ejecutivo.

Reproduce el comportamiento transversal de app/main.py (CORS, cabeceras de seguridad y
respuesta 503 ante fallas de MySQL) y agrega:
- X-SGSC-Service, para comprobar en el gateway qué servicio respondió.
- /health (proceso vivo) y /health/db (conexión a MySQL) propios de cada servicio.
- Documentación OpenAPI desactivada salvo SGSC_DOCS=true (uso local).
"""
import logging
import os

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from sgsc_common.database import get_db

DEFAULT_ORIGINS = 'http://localhost:5173,http://127.0.0.1:5173'


def health_router(service):
    router = APIRouter(tags=['Sistema'])

    @router.get('/health')
    def health():
        return {'status': 'ok', 'service': service}

    @router.get('/health/db')
    def database_health(db: Session = Depends(get_db)):
        try:
            db.execute(text('SELECT 1'))
            return {'status': 'ok', 'service': service, 'database': 'connected'}
        except Exception:
            raise HTTPException(status_code=503, detail='No se pudo conectar a MySQL.')

    return router


def create_app(service, title, description):
    docs = os.getenv('SGSC_DOCS', 'false').lower() == 'true'
    app = FastAPI(title=title, version='0.1.0', description=description,
                  docs_url='/docs' if docs else None, redoc_url='/redoc' if docs else None,
                  openapi_url='/openapi.json' if docs else None)
    app.state.service = service

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[s.strip() for s in os.getenv('CORS_ORIGINS', DEFAULT_ORIGINS).split(',') if s.strip()],
        allow_credentials=False,
        allow_methods=['*'],
        allow_headers=['*'],
    )

    @app.exception_handler(SQLAlchemyError)
    async def database_error(request: Request, exc: SQLAlchemyError):
        logging.getLogger(__name__).error('Database request failed: %s', type(exc).__name__)
        return JSONResponse(status_code=503, content={'detail': 'No se pudo consultar la base de datos. Intenta nuevamente.'})

    @app.middleware('http')
    async def no_cache(request: Request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-SGSC-Service'] = service
        return response

    app.include_router(health_router(service))
    return app
