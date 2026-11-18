"""El microservicio indicadores es independiente: solo importa su propio paquete, la librería
transversal sgsc_common y dependencias de terceros. No importa el monolito (app), otro
microservicio ni clientes HTTP para llamar a otros servicios."""
import ast
from pathlib import Path

PACKAGE = 'sgsc_indicadores'
SOURCE = Path(__file__).resolve().parents[1] / PACKAGE
OTHER_SERVICES = {'sgsc_indicadores', 'sgsc_detalle', 'sgsc_registro', 'sgsc_reportes'} - {PACKAGE}
FORBIDDEN = {'app', 'httpx', 'requests', 'aiohttp', 'urllib3', *OTHER_SERVICES}


def imported_roots():
    for path in SOURCE.rglob('*.py'):
        for node in ast.walk(ast.parse(path.read_text(encoding='utf-8'))):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    yield path.name, alias.name.split('.')[0]
            elif isinstance(node, ast.ImportFrom) and node.level == 0:
                yield path.name, node.module.split('.')[0]


def test_imports_only_its_package_the_common_library_and_third_parties():
    found = sorted({(name, root) for name, root in imported_roots() if root in FORBIDDEN or root == 'urllib'})
    assert found == [], found


def test_package_does_not_reference_other_service_hosts():
    text = ' '.join(p.read_text(encoding='utf-8') for p in SOURCE.rglob('*.py'))
    for host in ['indicadores:8000', 'detalle:8000', 'registro:8000', 'reportes:8000', 'nucleo:8000']:
        assert host not in text
