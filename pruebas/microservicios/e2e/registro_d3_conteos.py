"""Solo lectura: municipio de NL con colonias, conteos de pruebas previas y totales (solo números)."""
from sqlalchemy import text

from sgsc_common.database import engine

with engine.connect() as c:
    c.execute(text('SET SESSION TRANSACTION READ ONLY'))
    eid = c.execute(text("SELECT id FROM INEGI_Cat_Entidades WHERE cve_ent='19'")).scalar()
    print('Entidad NL id:', eid)
    mun = c.execute(text('''SELECT m.id, m.nom_mun, COUNT(c.id) AS n FROM INEGI_Cat_Municipios m
        JOIN Cat_Colonias c ON c.municipio_id=m.id AND c.is_active=1 WHERE m.entidad_id=:e
        GROUP BY m.id, m.nom_mun ORDER BY n DESC LIMIT 3'''), {'e': eid}).all()
    print('Municipios con más colonias activas:', [(m.id, m.nom_mun, m.n) for m in mun])
    if mun:
        col = c.execute(text('''SELECT id, nombre, codigo_postal FROM Cat_Colonias WHERE municipio_id=:m AND is_active=1
            ORDER BY id LIMIT 1'''), {'m': mun[0].id}).one()
        print('Colonia de catálogo (primera activa):', tuple(col))
    q = lambda sql: c.execute(text(sql)).scalar()
    print('Pruebas previas -> beneficiarios "PRUEBA%":', q("SELECT COUNT(*) FROM Tbl_Beneficiarios WHERE ben_gen_name LIKE 'PRUEBA%'"),
          '| solicitudes con "[PRUEBA":', q("SELECT COUNT(*) FROM Tbl_SolicitudesApoyo WHERE solapoyo_descripcion LIKE '%[PRUEBA%'"))
    print('Totales -> solicitudes:', q('SELECT COUNT(*) FROM Tbl_SolicitudesApoyo'), '| beneficiarios:', q('SELECT COUNT(*) FROM Tbl_Beneficiarios'),
          '| solicitantes:', q('SELECT COUNT(*) FROM Tbl_Solicitantes'), '| ejecutivo_registro:', q('SELECT COUNT(*) FROM ejecutivo_registro'))
