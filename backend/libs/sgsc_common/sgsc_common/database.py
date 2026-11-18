"""Conexión a MySQL de los microservicios del Ejecutivo.

Misma configuración que app/database.py (TLS con CERT_REQUIRED y verificación del nombre
del servidor). Diferencias: el archivo .env solo se carga si SGSC_ENV_FILE lo indica (en los
contenedores las variables llegan de Docker Compose) y el pool se ajusta por variables para
no exceder el límite de conexiones de Aiven al ejecutar varios servicios.
"""
import os
import ssl
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker

if os.getenv('SGSC_ENV_FILE') and Path(os.environ['SGSC_ENV_FILE']).is_file():
    load_dotenv(os.environ['SGSC_ENV_FILE'])

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_NAME = os.getenv("DB_NAME", "siesas-v2")
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

DATABASE_URL = URL.create(
    drivername="mysql+pymysql",
    username=DB_USER,
    password=DB_PASSWORD,
    host=DB_HOST,
    port=DB_PORT,
    database=DB_NAME,
    query={"charset": "utf8mb4"},
)

connect_args = {"connect_timeout": 10, "read_timeout": 20, "write_timeout": 20}
if os.getenv("DB_SSL", "false").lower() == "true":
    connect_args["ssl"] = ssl.create_default_context(cafile=os.getenv("DB_SSL_CA") or None)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    hide_parameters=True,
    pool_recycle=int(os.getenv("DB_POOL_RECYCLE", "280")),
    pool_size=int(os.getenv("DB_POOL_SIZE", "5")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "10")),
    connect_args=connect_args,
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
