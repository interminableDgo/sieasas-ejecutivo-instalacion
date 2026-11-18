"""Solo lectura: verifica la solicitud sintética SID con clave CLAVE (variables de entorno).
Imprime únicamente datos sintéticos de la prueba, identificadores y verificaciones."""
import json
import os

from sqlalchemy import text

from sgsc_common.database import engine

SID, CLAVE = int(os.environ['SID']), os.environ['CLAVE']
with engine.connect() as c:
    c.execute(text('SET SESSION TRANSACTION READ ONLY'))
    q = lambda sql, **p: c.execute(text(sql), p)
    sa = q('''SELECT solapoyo_id, solapoyo_beneficiarioid AS ben, solapoyo_solicitanteid AS sol, solapoyo_statusid AS estatus,
        solapoyo_tipoapoyoid AS tipo, solapoyo_enviadoporid AS origen, solapoyo_canalrecepcionid AS canal,
        solapoyo_unidadtratanteid AS unidad, createdBy, LEFT(solapoyo_descripcion, 45) AS descripcion
        FROM Tbl_SolicitudesApoyo WHERE solapoyo_id=:s''', s=SID).mappings().one()
    b = q('''SELECT ben_id, ben_gen_name, ben_gen_lastname, ben_gen_curp, ben_gen_birthdate, ben_dom_entidad, ben_dom_municipio,
        ben_dom_colonia_id, ben_dom_cp, createdBy FROM Tbl_Beneficiarios WHERE ben_id=:b''', b=sa['ben']).mappings().one()
    s = q('''SELECT sol_id, sol_nombres, sol_apellidos, sol_parentescoid, sol_municipioid, sol_colonia_id, sol_codigopostal,
        sol_telefono, sol_estadoid, createdBy FROM Tbl_Solicitantes WHERE sol_id=:x''', x=sa['sol']).mappings().one()
    er = q('SELECT solicitud_id, usuario_id, idempotencia FROM ejecutivo_registro WHERE idempotencia=:k', k=CLAVE).mappings().all()
    estatus = q('SELECT descripcion FROM Cat_StatusAtencion WHERE id=:i', i=sa['estatus']).scalar()
    cuenta = lambda sql, **p: q(sql, **p).scalar()
    resultado = {
        'solicitud': dict(sa), 'estatus': estatus, 'beneficiario': dict(b), 'solicitante': dict(s),
        'ejecutivo_registro': [dict(r) for r in er],
        'verificaciones': {
            'folio_es_el_id': True,
            'estatus_inicio': estatus == 'Inicio',
            'beneficiario_sintetico_sin_curp': b['ben_gen_name'] == 'PRUEBA E2E SGSC' and b['ben_gen_curp'] is None,
            'beneficiario_en_NL_Monterrey_Centro': (b['ben_dom_entidad'], b['ben_dom_municipio'], b['ben_dom_colonia_id'], b['ben_dom_cp']) == (19, 1003, 1, '64000'),
            'solicitante_copia_domicilio': (s['sol_municipioid'], s['sol_colonia_id'], s['sol_codigopostal']) == (1003, 1, '64000'),
            'solicitante_telefono_sintetico': s['sol_telefono'] == '0000000000',
            'una_fila_ejecutivo_registro_con_la_clave': len(er) == 1 and er[0]['solicitud_id'] == SID,
            'mismo_autor_en_las_4_tablas': len({sa['createdBy'], b['createdBy'], s['createdBy'], er[0]['usuario_id'] if er else None}) == 1,
            'descripcion_marcada_no_atender': sa['descripcion'].startswith('[PRUEBA AUTOMATIZADA SGSC'),
            'solicitudes_marcadas_en_total': cuenta("SELECT COUNT(*) FROM Tbl_SolicitudesApoyo WHERE solapoyo_descripcion LIKE '[PRUEBA AUTOMATIZADA SGSC%'"),
            'beneficiarios_sinteticos_de_esta_prueba': cuenta("SELECT COUNT(*) FROM Tbl_Beneficiarios WHERE ben_gen_name='PRUEBA E2E SGSC' AND ben_gen_lastname='REGISTRO SINTETICO 17NOV2026'"),
            'solicitantes_sinteticos_de_esta_prueba': cuenta("SELECT COUNT(*) FROM Tbl_Solicitantes WHERE sol_nombres='PRUEBA E2E SGSC' AND sol_apellidos='SOLICITANTE SINTETICO'"),
        },
        'conteos_despues': {t: cuenta(f'SELECT COUNT(*) FROM {t}') for t in ('Tbl_SolicitudesApoyo', 'Tbl_Beneficiarios', 'Tbl_Solicitantes', 'ejecutivo_registro')},
    }
    print(json.dumps(resultado, ensure_ascii=False, default=str, indent=1))
