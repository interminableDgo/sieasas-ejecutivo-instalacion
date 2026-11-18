"""Solo lectura: catálogos activos que exige el POST de Registro (sin datos personales)."""
from sqlalchemy import text

from sgsc_common.database import engine

TABLAS = ['Cat_TipoApoyo', 'Cat_EnviadoPor', 'Cat_CanalesRecepcion', 'Cat_UnidadesTratantes', 'Cat_Generos',
          'Cat_SeguridadSocial', 'Cat_GruposVulnerables', 'Cat_ConQuienVive', 'Cat_Parentescos']
with engine.connect() as c:
    c.execute(text('SET SESSION TRANSACTION READ ONLY'))
    print('Estatus inicial:', c.execute(text("SELECT id, descripcion FROM Cat_StatusAtencion WHERE descripcion='Inicio' AND is_active=1")).all())
    for t in TABLAS:
        filas = c.execute(text(f'SELECT id, descripcion FROM `{t}` WHERE is_active=1 ORDER BY id')).all()
        print(f'{t} ({len(filas)}):', '; '.join(f'{i}={d}' for i, d in filas)[:330])
