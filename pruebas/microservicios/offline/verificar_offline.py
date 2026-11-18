"""Verificación bloqueante de la configuración efectiva offline. No imprime valores.
Sale con código 1 si encuentra cualquier referencia a la base real (.env, ca.pem, Aiven o un DB_HOST real)."""
import json
import subprocess
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent / 'salida'
REPO = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
DOCKER = sys.argv[2] if len(sys.argv) > 2 else 'docker'
CMD = [DOCKER, 'compose', '-p', 'sgsc-offline', '-f', str(OUT / 'compose.offline.yml'),
       '--env-file', str(OUT / 'offline.env'), 'config', '--format', 'json']

result = subprocess.run(CMD, capture_output=True, text=True, encoding='utf-8')
if result.returncode:
    print('FALLA: docker compose config terminó con código', result.returncode)
    sys.exit(1)
config = json.loads(result.stdout)
text = json.dumps(config).lower().replace('\\\\', '/')
problems = []

for needle in ['backend/.env', '/.env"', 'backend/ca.pem', 'aiven']:
    if needle in text:
        problems.append(f'aparece una referencia prohibida ({needle!r})')

for name, service in config['services'].items():
    env = service.get('environment') or {}
    if env.get('DB_HOST', 'db.invalid') != 'db.invalid':
        problems.append(f'{name}: DB_HOST no es db.invalid')
    if 'DB_SSL' in env and env['DB_SSL'] != 'false':
        problems.append(f'{name}: DB_SSL no es false')
    for key in env:
        if key.startswith('SMTP_') or key in ('AUTH_ENCRYPTION_KEY', 'RESET_URL'):
            problems.append(f'{name}: recibe {key}')
    if service.get('ports') and name != 'gateway':
        problems.append(f'{name}: publica puertos')
    for item in service.get('env_file') or []:
        path = item['path'] if isinstance(item, dict) else item
        if Path(path).resolve() != (OUT / 'offline.env').resolve():
            problems.append(f'{name}: env_file distinto del offline')
    for volume in service.get('volumes') or []:
        source = Path(volume.get('source', ''))
        if REPO in source.parents or source == REPO:
            problems.append(f'{name}: monta una ruta del repositorio')

secret = Path(config.get('secrets', {}).get('db_ca', {}).get('file', ''))
if secret.resolve() != (OUT / 'ca-ficticio.pem').resolve():
    problems.append('secrets.db_ca no es el ca-ficticio.pem generado')
if config.get('name') != 'sgsc-offline':
    problems.append('el proyecto no se llama sgsc-offline')
if not config['services'].get('gateway', {}).get('ports'):
    problems.append('el gateway no publica puerto')

if problems:
    print('FALLA (no se levantarán contenedores):')
    for p in problems:
        print(' -', p)
    sys.exit(1)
print(f'OK: {len(config["services"])} servicios; sin referencias a .env, ca.pem ni Aiven; '
      'solo el gateway publica puerto; secreto y env_file ficticios.')
