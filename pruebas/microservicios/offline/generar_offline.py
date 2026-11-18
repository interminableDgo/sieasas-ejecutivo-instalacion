"""Genera un Compose de SGSC totalmente aislado de cualquier base real a partir de docker-compose.yml.

Uso (desde la raíz del repositorio):  python pruebas/microservicios/offline/generar_offline.py
Luego:  python pruebas/microservicios/offline/verificar_offline.py   (bloquea si detecta datos reales)
        docker compose -p sgsc-offline -f pruebas/microservicios/offline/salida/compose.offline.yml
          --env-file pruebas/microservicios/offline/salida/offline.env up -d --build

Es un archivo independiente (no se combina con -f): no conserva env_file, secretos ni
interpolaciones del original. docker-compose.yml no se modifica.
"""
import sys
from pathlib import Path

import yaml

REPO = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / 'salida'  # ignorada por git
OUT.mkdir(exist_ok=True)
WEB = OUT / 'web'
WEB.mkdir(exist_ok=True)

FAKE = {'DB_HOST': 'db.invalid', 'DB_PORT': '1', 'DB_NAME': 'offline', 'DB_USER': 'offline',
        'DB_PASSWORD': 'offline', 'DB_SSL': 'false'}
(OUT / 'offline.env').write_text(''.join(f'{k}={v}\n' for k, v in FAKE.items()) +
                                 'CORS_ORIGINS=http://localhost:8080,http://127.0.0.1:8080\n', encoding='utf-8')
(OUT / 'ca-ficticio.pem').write_text('marcador offline: no es un certificado\n', encoding='utf-8')

source = yaml.safe_load((REPO / 'docker-compose.yml').read_text(encoding='utf-8'))
compose = {'name': 'sgsc-offline', 'services': {}, 'networks': source['networks'],
           'secrets': {'db_ca': {'file': str(OUT / 'ca-ficticio.pem')}}}

for name, service in source['services'].items():
    service = dict(service)
    build = service['build']
    if isinstance(build, str):
        service['build'] = str((REPO / build).resolve())
    else:
        service['build'] = {**build, 'context': str((REPO / build['context']).resolve())}
    service['image'] = service['image'].replace('sgsc-', 'sgsc-offline-', 1)
    service.pop('env_file', None)
    if name == 'gateway':
        service['ports'] = ['127.0.0.1:8080:80']
        service['volumes'] = [f'{WEB}:/usr/share/nginx/html:ro']
    elif name == 'nucleo':
        service['env_file'] = [str(OUT / 'offline.env')]
        service['environment'] = {'DB_SSL_CA': '/run/secrets/db_ca', 'FORWARDED_ALLOW_IPS': '172.30.0.10'}
    else:
        env = dict(service['environment'])
        env.update(FAKE)
        env.update({'DB_POOL_SIZE': '2', 'DB_MAX_OVERFLOW': '2',
                    'CORS_ORIGINS': 'http://localhost:8080,http://127.0.0.1:8080'})
        service['environment'] = env
    compose['services'][name] = service

text = yaml.safe_dump(compose, sort_keys=False, allow_unicode=True)
assert '${' not in text, 'Quedó una interpolación'
(OUT / 'compose.offline.yml').write_text('# Generado por generar_offline.py: SGSC sin Aiven.\n' + text, encoding='utf-8')
print('Generado', OUT / 'compose.offline.yml')
