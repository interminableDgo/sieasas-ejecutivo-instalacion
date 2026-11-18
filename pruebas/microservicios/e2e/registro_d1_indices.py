"""Solo lectura: índices únicos de las tablas que escribe el POST de Registro."""
from sqlalchemy import text

from sgsc_common.database import engine

with engine.connect() as c:
    c.execute(text('SET SESSION TRANSACTION READ ONLY'))
    for t in ('Tbl_Beneficiarios', 'Tbl_Solicitantes', 'Tbl_SolicitudesApoyo', 'ejecutivo_registro'):
        idx = c.execute(text(f'SHOW INDEX FROM `{t}` WHERE Non_unique=0')).mappings().all()
        print(t, '-> únicos:', sorted({(i['Key_name'], i['Column_name']) for i in idx}))
