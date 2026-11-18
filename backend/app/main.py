import os
import logging
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError
from fastapi.middleware.cors import CORSMiddleware

from app.routers import health, auth, executive, ciudadano

app = FastAPI(
    title="SGSC Salud API",
    version="0.1.0",
    description="Backend FastAPI para la Vista Ejecutiva del SGSC.",
)

# Desarrollo local:
# - Flutter mobile no necesita CORS.
# - Flutter web sí.
# En producción se deben reemplazar los orígenes "*" por dominios permitidos.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[s.strip() for s in os.getenv('CORS_ORIGINS','https://localhost:5173,https://127.0.0.1:5173').split(',') if s.strip()],
    # La versión web del Ciudadano se publica en Netlify (cualquier subdominio *.netlify.app).
    # El API usa tokens Bearer, no cookies, por lo que permitir ese origen no expone sesiones.
    allow_origin_regex=os.getenv('CORS_ORIGIN_REGEX', r'https://[a-z0-9-]+\.netlify\.app'),
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(executive.router)
app.include_router(ciudadano.router)


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
    return response


@app.get("/")
def root():
    return {
        "proyecto": "SGSC Salud",
        "api": "FastAPI",
        "estado": "online",
        "docs": "/docs",
    }
