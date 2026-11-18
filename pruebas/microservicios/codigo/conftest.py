"""Permite importar en la misma prueba el monolito (backend/app), la librería común y los
cuatro microservicios, sin instalarlos. Ninguna prueba de esta carpeta usa la base de datos."""
import os
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[3] / 'backend'
SERVICES = ['indicadores', 'detalle', 'registro', 'reportes']

for path in [BACKEND, BACKEND / 'libs' / 'sgsc_common', *(BACKEND / 'services' / s for s in SERVICES)]:
    sys.path.insert(0, str(path))

# Variables definidas antes de importar: load_dotenv no las reemplaza, así que ningún import
# puede conectarse a Aiven aunque exista backend/.env.
for key, value in {'DB_HOST': 'db.invalid', 'DB_PORT': '1', 'DB_USER': 'sin-acceso',
                   'DB_PASSWORD': 'sin-acceso', 'DB_SSL': 'false'}.items():
    os.environ[key] = value
