# -*- coding: utf-8 -*-
"""Extrae SOLO la estructura de una base MySQL (sin datos) a JSON.

Usa las mismas variables de conexión que el backend: DB_HOST, DB_PORT, DB_NAME, DB_USER,
DB_PASSWORD, DB_SSL y DB_SSL_CA.

    python esquema.py salida.json
"""
import json
import os
import ssl
import sys

import pymysql

salida = sys.argv[1]
ctx = None
if os.getenv('DB_SSL', 'false').lower() == 'true':
    ctx = ssl.create_default_context(cafile=os.getenv('DB_SSL_CA') or None)
bd = os.environ['DB_NAME']
con = pymysql.connect(host=os.getenv('DB_HOST', '127.0.0.1'), port=int(os.getenv('DB_PORT', '3306')),
                      user=os.environ['DB_USER'], password=os.getenv('DB_PASSWORD', ''), database=bd,
                      ssl=ctx, connect_timeout=20)
cur = con.cursor(pymysql.cursors.DictCursor)
cur.execute('SET SESSION TRANSACTION READ ONLY')


def q(sql, *args):
    cur.execute(sql, args)
    return cur.fetchall()


info = {'bd': bd, 'version': q('SELECT VERSION() v')[0]['v'], 'tablas': {}}
for t in q("SELECT TABLE_NAME, ENGINE, TABLE_COLLATION FROM information_schema.TABLES "
           "WHERE TABLE_SCHEMA=%s AND TABLE_TYPE='BASE TABLE'", bd):
    info['tablas'][t['TABLE_NAME']] = {'engine': t['ENGINE'], 'collation': t['TABLE_COLLATION'],
                                      'columnas': {}, 'indices': {}, 'fks': {}}
for c in q("""SELECT TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA,
                     CHARACTER_SET_NAME, COLLATION_NAME
              FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=%s ORDER BY TABLE_NAME, ORDINAL_POSITION""", bd):
    if c['TABLE_NAME'] in info['tablas']:
        info['tablas'][c['TABLE_NAME']]['columnas'][c['COLUMN_NAME']] = {
            'pos': c['ORDINAL_POSITION'], 'tipo': c['COLUMN_TYPE'], 'nulo': c['IS_NULLABLE'] == 'YES',
            'default': c['COLUMN_DEFAULT'], 'extra': c['EXTRA'], 'charset': c['CHARACTER_SET_NAME'],
            'collation': c['COLLATION_NAME']}
for s in q("""SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE, COLUMN_NAME FROM information_schema.STATISTICS
              WHERE TABLE_SCHEMA=%s ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX""", bd):
    if s['TABLE_NAME'] in info['tablas']:
        ix = info['tablas'][s['TABLE_NAME']]['indices'].setdefault(
            s['INDEX_NAME'], {'unico': not s['NON_UNIQUE'], 'columnas': []})
        ix['columnas'].append(s['COLUMN_NAME'])
for f in q("""SELECT k.TABLE_NAME, k.CONSTRAINT_NAME, k.COLUMN_NAME, k.REFERENCED_TABLE_NAME, k.REFERENCED_COLUMN_NAME,
                     r.UPDATE_RULE, r.DELETE_RULE
              FROM information_schema.KEY_COLUMN_USAGE k
              JOIN information_schema.REFERENTIAL_CONSTRAINTS r
                ON r.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME=k.CONSTRAINT_NAME
               AND r.TABLE_NAME=k.TABLE_NAME
              WHERE k.TABLE_SCHEMA=%s AND k.REFERENCED_TABLE_NAME IS NOT NULL ORDER BY k.ORDINAL_POSITION""", bd):
    if f['TABLE_NAME'] in info['tablas']:
        fk = info['tablas'][f['TABLE_NAME']]['fks'].setdefault(f['CONSTRAINT_NAME'], {
            'columnas': [], 'ref_tabla': f['REFERENCED_TABLE_NAME'], 'ref_columnas': [],
            'update': f['UPDATE_RULE'], 'delete': f['DELETE_RULE']})
        fk['columnas'].append(f['COLUMN_NAME'])
        fk['ref_columnas'].append(f['REFERENCED_COLUMN_NAME'])
json.dump(info, open(salida, 'w', encoding='utf-8'), ensure_ascii=False, indent=1, default=str)
print('%s: MySQL %s, %d tablas' % (bd, info['version'], len(info['tablas'])))
con.close()
