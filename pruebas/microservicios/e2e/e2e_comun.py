"""Utilidades comunes del E2E de SGSC (Playwright sobre el Chrome visible, vía CDP local).

- Nunca imprime ni guarda el encabezado Authorization: el monitor solo conserva método, ruta
  (sin consulta), código, tiempo y la cabecera X-SGSC-Service.
- Sin trazas, videos ni HAR de Playwright.
"""
import time
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

APP = 'http://localhost:8080'
CDP = 'http://127.0.0.1:9223'


def conectar(pw):
    browser = pw.chromium.connect_over_cdp(CDP)
    page = next(p for c in browser.contexts for p in c.pages if p.url.startswith(APP))
    return browser, page


def activar_semantica(page):
    """Flutter web dibuja en canvas; el árbol de accesibilidad expone los controles al DOM."""
    if page.locator('flt-semantics').count() > 5:
        return
    placeholder = page.locator('flt-semantics-placeholder')
    if placeholder.count():
        placeholder.first.dispatch_event('click')
    page.wait_for_timeout(800)


def elementos(page, limite=400):
    """Etiquetas visibles del árbol de semántica (para descubrir selectores)."""
    return page.evaluate('''(limite) => {
      const out = [];
      for (const el of document.querySelectorAll('flt-semantics, input, textarea')) {
        const role = el.getAttribute('role') || el.tagName.toLowerCase();
        const label = (el.getAttribute('aria-label') || el.innerText || el.getAttribute('placeholder') || '').trim();
        if (!label && !['textbox','input','button'].includes(role)) continue;
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) continue;
        out.push(role + ' | ' + label.replace(/\\s+/g, ' ').slice(0, 90));
        if (out.length >= limite) break;
      }
      return out;
    }''', limite)


class Monitor:
    """Registra las peticiones a la API: ruta sin consulta, servicio, código y tiempo."""

    def __init__(self, page):
        self.registros = []
        self._token = None
        self.page = page
        page.on('requestfinished', self._fin)
        page.on('requestfailed', self._fallo)

    def _api(self, url):
        path = urlsplit(url).path
        return path.startswith(('/ejecutivo/', '/auth/', '/health'))

    def _fin(self, request):
        if not self._api(request.url):
            return
        response = request.response()
        headers = response.all_headers() if response else {}
        auth = request.header_value('authorization')
        if auth and auth.startswith('Bearer '):
            self._token = auth[7:]  # solo en memoria
        timing = request.timing
        ms = round(timing['responseEnd']) if timing and timing.get('responseEnd', -1) >= 0 else None
        self.registros.append({'t': time.strftime('%H:%M:%S'), 'metodo': request.method,
                               'ruta': urlsplit(request.url).path, 'codigo': response.status if response else None,
                               'servicio': headers.get('x-sgsc-service', 'nucleo' if urlsplit(request.url).path.startswith(('/auth', '/health')) else '?'),
                               'ms': ms, 'consulta': sorted({kv.split('=')[0] for kv in urlsplit(request.url).query.split('&') if kv})})

    def _fallo(self, request):
        if self._api(request.url):
            self.registros.append({'t': time.strftime('%H:%M:%S'), 'metodo': request.method,
                                   'ruta': urlsplit(request.url).path, 'codigo': 'FALLO', 'servicio': '-', 'ms': None,
                                   'error': request.failure})

    def token(self):
        return self._token

    def desde(self, n):
        return self.registros[n:]
