"""Enrutamiento del gateway sin Docker.

Lee gateway/nginx.conf, aplica el algoritmo de selección de `location` de Nginx
(exacta =, prefijo más largo, ^~, expresiones regulares en orden, prefijo como último
recurso) y comprueba a qué servicio llega cada ruta. Las rutas de la App Ejecutiva se
extraen del código Flutter, de modo que una ruta nueva sin enrutar hace fallar la prueba.
La validación de sintaxis con `nginx -t` queda para cuando Docker esté disponible.
"""
import re
from dataclasses import dataclass
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
CONF = (ROOT / 'gateway' / 'nginx.conf').read_text(encoding='utf-8')
FLUTTER = ROOT / 'sgsc_ejecutiva' / 'lib'


@dataclass
class Location:
    modifier: str
    pattern: str
    body: str

    def target(self, method, match):
        if 'proxy_pass http://$solicitudes_up' in self.body:
            return 'registro' if method == 'POST' else 'detalle'
        service = re.search(r'set \$servicio (\S+);', self.body)
        if service:
            value = service.group(1)
            return match.group(1) if value == '$1' else value
        status = re.search(r'return (\d{3})', self.body)
        if status:
            return status.group(1)
        if 'root /usr/share/nginx/html' in self.body:
            return 'flutter'
        raise AssertionError(f'Ubicación sin destino: {self.pattern}')


def strip_comments(text):
    return '\n'.join(line.split('#', 1)[0] if not line.lstrip().startswith('#') else '' for line in text.splitlines())


def parse_locations(text):
    text = strip_comments(text)
    found = []
    for head in re.finditer(r'location\s+(=|~\*|~|\^~)?\s*([^\s{]+)\s*\{', text):
        depth, i = 1, head.end()
        while depth:
            depth += {'{': 1, '}': -1}.get(text[i], 0)
            i += 1
        found.append(Location(head.group(1) or '', head.group(2), text[head.end():i - 1]))
    return [loc for loc in found if not loc.pattern.startswith('@')]


LOCATIONS = parse_locations(CONF)


def route(uri, method='GET'):
    for loc in LOCATIONS:
        if loc.modifier == '=' and uri == loc.pattern:
            return loc.target(method, None)
    prefixes = [loc for loc in LOCATIONS if loc.modifier in ('', '^~') and uri.startswith(loc.pattern)]
    longest = max(prefixes, key=lambda loc: len(loc.pattern), default=None)
    if longest and longest.modifier == '^~':
        return longest.target(method, None)
    for loc in LOCATIONS:
        if loc.modifier in ('~', '~*'):
            match = re.search(loc.pattern, uri, re.I if loc.modifier == '~*' else 0)
            if match:
                return loc.target(method, match)
    assert longest, uri
    return longest.target(method, None)


EXPECTED = [
    # Indicadores y Filtros
    ('GET', '/ejecutivo/dashboard', 'indicadores'),
    ('GET', '/ejecutivo/comparacion', 'indicadores'),
    ('GET', '/ejecutivo/catalogos', 'indicadores'),
    # Detalle de Indicadores
    ('GET', '/ejecutivo/solicitudes', 'detalle'),
    ('OPTIONS', '/ejecutivo/solicitudes', 'detalle'),
    ('GET', '/ejecutivo/solicitudes/sugerencias', 'detalle'),
    ('GET', '/ejecutivo/solicitudes/9', 'detalle'),
    ('GET', '/ejecutivo/solicitudes/abc', 'detalle'),  # FastAPI responde 422, como hoy
    # Registro Ejecutivo
    ('POST', '/ejecutivo/solicitudes', 'registro'),
    ('GET', '/ejecutivo/personas', 'registro'),
    ('GET', '/ejecutivo/colonias', 'registro'),
    ('GET', '/ejecutivo/municipios-nacimiento', 'registro'),
    # Reportes y Exportación
    ('GET', '/ejecutivo/exportar/xlsx', 'reportes'),
    ('GET', '/ejecutivo/exportar/pdf', 'reportes'),
    ('GET', '/ejecutivo/exportar/csv', 'reportes'),  # FastAPI responde 422, como hoy
    # Núcleo
    ('POST', '/auth/login', 'nucleo'),
    ('POST', '/auth/verify', 'nucleo'),
    ('GET', '/auth/me', 'nucleo'),
    ('POST', '/auth/logout', 'nucleo'),
    ('POST', '/auth/forgot-password', 'nucleo'),
    ('POST', '/auth/reset-password', 'nucleo'),
    ('POST', '/auth/request-access', 'nucleo'),
    ('GET', '/health', 'nucleo'),
    ('GET', '/health/db', 'nucleo'),
    # Salud por servicio
    ('GET', '/health/indicadores', 'indicadores'),
    ('GET', '/health/detalle', 'detalle'),
    ('GET', '/health/registro', 'registro'),
    ('GET', '/health/reportes', 'reportes'),
    # No publicadas
    ('GET', '/ejecutivo/desconocida', '404'),
    ('GET', '/ejecutivo/dashboard/extra', '404'),
    ('GET', '/ejecutivo/solicitudes/9/extra', '404'),
    ('POST', '/ciudadano/login', '404'),
    ('GET', '/ciudadano/solicitudes', '404'),
    ('GET', '/docs', '404'),
    ('GET', '/redoc', '404'),
    ('GET', '/openapi.json', '404'),
    ('GET', '/docs/oauth2-redirect', '404'),
    # App Ejecutiva web
    ('GET', '/', 'flutter'),
    ('GET', '/main.dart.js', 'flutter'),
    ('GET', '/restablecer', 'flutter'),
]


@pytest.mark.parametrize('method,uri,service', EXPECTED)
def test_route_table(method, uri, service):
    assert route(uri, method) == service


def flutter_routes():
    routes = set()
    for path in FLUTTER.rglob('*.dart'):
        for literal in re.findall(r"'(/(?:auth|ejecutivo)/[^']*)'", path.read_text(encoding='utf-8')):
            routes.add(re.sub(r'\$\{[^}]+\}|\$\w+', '9', literal))
    return sorted(routes)


def test_flutter_uses_the_routes_listed_in_the_table():
    # Si Flutter agrega una ruta, debe incorporarse explícitamente a EXPECTED.
    listed = {uri for _, uri, _ in EXPECTED}
    used = {uri.replace('/exportar/9', '/exportar/pdf') for uri in flutter_routes()}
    assert len(used) == 16, used
    assert used <= listed, used - listed


@pytest.mark.parametrize('uri', flutter_routes())
def test_every_flutter_route_reaches_a_service(uri):
    for method in ('GET', 'POST'):
        assert route(uri, method) in {'nucleo', 'indicadores', 'detalle', 'registro', 'reportes'}, (method, uri)


def test_executive_catch_all_does_not_hide_regex_routes():
    catch_all = [loc for loc in LOCATIONS if loc.pattern == '/ejecutivo/']
    assert len(catch_all) == 1 and catch_all[0].modifier == '', 'Con ^~ ocultaría las rutas de los microservicios.'


def test_upstreams_are_resolved_at_request_time_and_auth_is_forwarded():
    assert 'resolver 127.0.0.11' in CONF
    proxied = [loc for loc in LOCATIONS if 'proxy_pass' in loc.body]
    assert proxied and all(re.search(r'proxy_pass http://\$\w+:8000', loc.body) for loc in proxied)
    # Authorization no se elimina ni se reescribe.
    assert 'proxy_set_header Authorization' not in CONF
    assert 'proxy_set_header X-Forwarded-For $remote_addr;' in CONF


def test_access_log_does_not_record_query_strings():
    log_format = re.search(r"log_format sgsc (.*?);", CONF, re.S).group(1)
    assert '$request ' not in log_format and '$request_uri' not in log_format and '$args' not in log_format
