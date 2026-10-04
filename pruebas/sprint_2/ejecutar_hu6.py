"""Run HU6/regression checks without reading .env or connecting to MySQL.
Set PDF_TEST_PYTHON to a Python with pypdf if the backend environment lacks it.
"""
import json
import os
from pathlib import Path
import subprocess
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[2]
evidence = root / 'pruebas/sprint_2/evidencias'
evidence.mkdir(parents=True, exist_ok=True)
python = root / 'backend/.venv/Scripts/python.exe'
flutter = json.loads((root / 'tools.local.json').read_text(encoding='utf-8'))['flutter']
env = os.environ.copy()
env.update(PYTHON_DOTENV_DISABLED='1', PYTHONIOENCODING='utf-8',
           DB_HOST='127.0.0.1', DB_PORT='1', DB_USER='hu6_isolated',
           DB_PASSWORD='synthetic', DB_NAME='hu6_isolated', DB_SSL='false',
           RUN_DB_TESTS='0', SCREENSHOT_DIR=str(evidence / 'interfaz'))
checks = [
    ('backend', root / 'backend', [str(python), '-m', 'pytest', '-v', '--junitxml=' + str(evidence / 'backend.xml')]),
    ('flutter', root / 'sgsc_ejecutiva', [flutter, 'test', '--no-pub', '--reporter', 'expanded']),
    ('analyze', root / 'sgsc_ejecutiva', [flutter, 'analyze', '--no-pub']),
    ('web', root / 'sgsc_ejecutiva', [flutter, 'build', 'web', '--no-pub', '--dart-define=API_BASE_URL=http://127.0.0.1:8000']),
]
results = []
for name, cwd, command in checks:
    print('Ejecutando:', name, flush=True)
    started = datetime.now(timezone.utc).isoformat()
    with (evidence / (name + '.txt')).open('w', encoding='utf-8') as output:
        process = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, check=False)
    results.append(dict(prueba=name, inicio_utc=started, codigo_salida=process.returncode, comando=command))
    print(name, 'código de salida:', process.returncode, flush=True)
(evidence / 'ejecucion.json').write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding='utf-8')
raise SystemExit(1 if any(r['codigo_salida'] for r in results) else 0)
