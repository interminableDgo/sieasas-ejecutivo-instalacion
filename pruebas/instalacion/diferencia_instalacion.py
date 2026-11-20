# -*- coding: utf-8 -*-
"""Compara la base SSNL antes y después de instalar el Ejecutivo.

Solo se permiten: las 5 tablas de catálogo nuevas y las 2 columnas de colonia (con su índice y FK).
Cualquier otro cambio sobre la base SSNL es un error."""
import json, sys
sys.stdout.reconfigure(encoding='utf-8')
antes = json.load(open(sys.argv[1], encoding='utf-8'))['tablas']
despues = json.load(open(sys.argv[2], encoding='utf-8'))['tablas']
low = lambda d: {k.lower(): v for k, v in d.items()}
antes, despues = low(antes), low(despues)
PERMITIDAS = {'cat_colonias', 'cat_conquienvive', 'cat_ocupaciones', 'cat_fuentesingreso', 'cat_areasestudio'}
COLUMNAS = {('tbl_beneficiarios', 'ben_dom_colonia_id'), ('tbl_solicitantes', 'sol_colonia_id')}
errores = []
nuevas = set(despues) - set(antes)
print('Tablas nuevas:', sorted(nuevas))
if nuevas != PERMITIDAS: errores.append('tablas nuevas inesperadas o faltantes: %s' % sorted(nuevas ^ PERMITIDAS))
if set(antes) - set(despues): errores.append('tablas de SSNL que desaparecieron: %s' % sorted(set(antes) - set(despues)))
for t in sorted(set(antes) & set(despues)):
    a, d = antes[t], despues[t]
    ca, cd = low(a['columnas']), low(d['columnas'])
    for c in sorted(set(cd) - set(ca)):
        print('Columna nueva: %s.%s %s' % (t, c, cd[c]['tipo']))
        if (t, c) not in COLUMNAS: errores.append('columna inesperada %s.%s' % (t, c))
    for c in sorted(set(ca) - set(cd)): errores.append('columna de SSNL que desapareció: %s.%s' % (t, c))
    for c in sorted(set(ca) & set(cd)):
        if ca[c] != cd[c]: errores.append('columna de SSNL modificada: %s.%s %s -> %s' % (t, c, ca[c], cd[c]))
    for nombre in set(a['indices']) - set(d['indices']): errores.append('índice de SSNL que desapareció: %s.%s' % (t, nombre))
    for nombre in set(a['fks']) - set(d['fks']): errores.append('FK de SSNL que desapareció: %s.%s' % (t, nombre))
    for nombre in set(d['fks']) - set(a['fks']):
        print('FK nueva: %s.%s %s -> %s' % (t, nombre, d['fks'][nombre]['columnas'], d['fks'][nombre]['ref_tabla']))
    if a['collation'] != d['collation']: errores.append('collation de %s modificada' % t)
colaciones = sorted({despues[t]['collation'] for t in nuevas})
print('Collation de las tablas nuevas:', colaciones)
print('\nRESULTADO:', 'sin cambios en SSNL; solo lo permitido' if not errores else 'ERRORES')
for e in errores: print('  -', e)
sys.exit(1 if errores else 0)
