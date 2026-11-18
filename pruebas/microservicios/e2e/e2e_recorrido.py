"""Recorrido E2E automatizado de SGSC: Flutter (Chrome real) -> Nginx -> microservicios -> Aiven.

Requiere una sesión ya iniciada en el Chrome visible (CDP 127.0.0.1:9223). Solo realiza
consultas de lectura desde la interfaz y, al final, el cierre de sesión (escritura autorizada).
El token se toma de los encabezados de la propia app y vive solo en memoria: no se imprime ni
se guarda. Las evidencias contienen rutas, nombres de parámetros, códigos, tiempos, servicios,
totales y aserciones; nunca nombres de personas, tokens ni credenciales.
Uso: e2e_recorrido.py <salida.json> <carpeta_descargas>
"""
import io
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import httpx
from openpyxl import load_workbook
from playwright.sync_api import sync_playwright
from pypdf import PdfReader

from e2e_comun import CDP, Monitor, activar_semantica, conectar

SALIDA, DESCARGAS = Path(sys.argv[1]), Path(sys.argv[2])
DESCARGAS.mkdir(parents=True, exist_ok=True)
GATEWAY, MONOLITO = 'http://localhost:8080', 'http://127.0.0.1:8000'
MUNICIPIO = 'Hidalgo'
INICIO, FIN = ('01/01/2025', '31/12/2025')
ESPERADO_SERVICIO = {'/ejecutivo/dashboard': 'indicadores', '/ejecutivo/comparacion': 'indicadores',
                     '/ejecutivo/catalogos': 'indicadores', '/ejecutivo/solicitudes': 'detalle',
                     '/ejecutivo/solicitudes/sugerencias': 'detalle', '/ejecutivo/exportar/xlsx': 'reportes',
                     '/ejecutivo/exportar/pdf': 'reportes'}

resultados, capturas, consola = [], [], []


def servicio_esperado(path):
    if re.fullmatch(r'/ejecutivo/solicitudes/\d+', path):
        return 'detalle'
    return ESPERADO_SERVICIO.get(path)


class Captura:
    def __init__(self, response, body):
        req = response.request
        self.url = response.url
        self.path = urlsplit(response.url).path
        self.params = {k: v for k, v in parse_qs(urlsplit(response.url).query).items()}
        self.status = response.status
        self.servicio = response.headers.get('x-sgsc-service', 'nucleo')
        t = req.timing
        self.ms = round(t['responseEnd']) if t and t.get('responseEnd', -1) >= 0 else None
        self.body = body
        self.metodo = req.method

    def json(self):
        return json.loads(self.body)

    def evidencia(self):
        return {'metodo': self.metodo, 'ruta': self.path, 'parametros': sorted(self.params), 'codigo': self.status,
                'servicio': self.servicio, 'servicio_esperado': servicio_esperado(self.path), 'ms': self.ms}


def capturar(page, rutas, accion, metodo='GET', timeout=40):
    """Ejecuta la acción de interfaz y espera las respuestas cuyas rutas coinciden (regex)."""
    vistos = {}

    def on(response):
        path = urlsplit(response.url).path
        if response.request.method != metodo:
            return
        for r in rutas:
            if r not in vistos and re.fullmatch(r, path):
                try:
                    body = response.body()
                except Exception:
                    body = b''
                vistos[r] = Captura(response, body)
    page.on('response', on)
    try:
        accion()
        fin = time.time() + timeout
        while len(vistos) < len(rutas) and time.time() < fin:
            page.wait_for_timeout(200)
    finally:
        page.remove_listener('response', on)
    for c in vistos.values():
        capturas.append(c)
    return vistos


def boton(page, patron, rol='button'):
    loc = page.get_by_role(rol, name=re.compile(patron))
    loc.first.wait_for(state='attached', timeout=15000)
    return loc.first


def clic(page, patron, rol='button', espera=900):
    boton(page, patron, rol).click(force=True)
    page.wait_for_timeout(espera)


def clic_visible(page, patron, rol='button', espera=900, intentos=20):
    """Desplaza el lienzo de Flutter hasta que el control quede dentro de la ventana y lo pulsa."""
    alto = page.evaluate('window.innerHeight')
    for _ in range(intentos):
        loc = page.get_by_role(rol, name=re.compile(patron))
        if loc.count():
            caja = loc.first.bounding_box()
            if caja and caja['y'] >= 60 and caja['y'] + caja['height'] <= alto - 10:
                # Clic real del ratón: Flutter no siempre atiende el clic sintético sobre el nodo de accesibilidad.
                page.mouse.click(caja['x'] + caja['width'] / 2, caja['y'] + caja['height'] / 2)
                page.wait_for_timeout(espera)
                return
            delta = 300 if (not caja or caja['y'] + caja['height'] > alto - 10) else -300
        else:
            delta = 400
        page.mouse.move(720, alto // 2)
        page.mouse.wheel(0, delta)
        page.wait_for_timeout(500)
    raise TimeoutError(f'control no visible: {patron}')


def etiquetas(page):
    return page.evaluate('''() => [...document.querySelectorAll('flt-semantics')]
      .map(e => (e.getAttribute('aria-label') || e.innerText || '').replace(/\\s+/g, ' ').trim()).filter(Boolean)''')


def _leer_resumen(page):
    for t in etiquetas(page):
        m = re.search(r'Solicitudes registradas (\d[\d,]*) (?:totales|solicitudes filtradas)', t)
        if m:
            act = re.search(r'(\d[\d,]*) activas', t)
            res = re.search(r'(\d[\d,]*) resueltas', t)
            n = lambda x: int(x.group(1).replace(',', '')) if x else None
            return {'total': n(m), 'activas': n(act), 'resueltas': n(res)}
    return None


def resumen_ui(page, esperado=None, segundos=10):
    """Totales de la tarjeta «Solicitudes registradas». Si se indica el total de la API, espera
    a que Flutter termine de redibujar (máx. `segundos`) y devuelve lo último que mostró."""
    ultimo = None
    fin = time.time() + segundos
    while time.time() < fin:
        leido = _leer_resumen(page)
        if leido:
            ultimo = leido
            if esperado is None or leido['total'] == esperado:
                return leido
        else:
            page.mouse.move(720, 500)
            page.mouse.wheel(0, -1500)
        page.wait_for_timeout(500)
    return ultimo


def registrar(escenario, esperado, obtenido, aprobado, cap=(), **extra):
    caps = [c.evidencia() for c in cap]
    servicio_ok = all(c['servicio'] == c['servicio_esperado'] for c in caps if c['servicio_esperado'])
    if aprobado is True and not servicio_ok:
        aprobado, obtenido = False, obtenido + ' | servicio distinto del esperado'
    resultados.append({'escenario': escenario, 'esperado': esperado, 'obtenido': obtenido,
                       'estado': {True: 'APROBADA', False: 'FALLIDA', None: 'OMITIDA'}[aprobado],
                       'peticiones': caps, **extra})
    print(f"[{resultados[-1]['estado']}] {escenario}: {obtenido}", flush=True)


def recuperar(page):
    """Cierra diálogos abiertos tras un fallo para que no afecte al siguiente escenario."""
    for _ in range(6):
        if page.get_by_role('button', name=re.compile('^Resumen$')).count():
            return
        descartar = page.get_by_role('button', name=re.compile('^(Descartar|Volver)$'))
        if descartar.count():
            descartar.first.click(force=True)
        else:
            page.keyboard.press('Escape')
        page.wait_for_timeout(700)


SOLO = {x.strip() for x in os.environ.get('SGSC_E2E_SOLO', '').split(',') if x.strip()}


def paso(escenario, esperado, fn):
    if SOLO and escenario.split()[0] not in SOLO:
        return
    try:
        fn()
    except Exception as exc:
        registrar(escenario, esperado, f'error de automatización: {type(exc).__name__}: {str(exc).splitlines()[0][:160]}', False)
        recuperar(PAGE)


def asegurar_resumen_sin_filtros(page):
    for _ in range(4):
        loc = page.get_by_role('button', name=re.compile('^Quitar filtro$'))
        if not loc.count():
            break
        capturar(page, [r'/ejecutivo/dashboard'], lambda: loc.first.click(force=True))
    clic(page, '^Resumen$')


def abrir_periodo(page, inicio, fin):
    # Sin «/» en la expresión: Playwright serializa el nombre como /regex/.
    clic(page, r'^Todo el historial$|^\d{2}.\d{2}.\d{4}')
    clic(page, '^Cambiar a modo de entrada$')
    campos = page.locator('input')
    campos.nth(0).click(force=True)
    page.keyboard.press('Control+A')
    page.keyboard.type(inicio, delay=30)
    campos.nth(1).click(force=True)
    page.keyboard.press('Control+A')
    page.keyboard.type(fin, delay=30)
    clic(page, '^Aplicar periodo$')


def elegir_municipio(page):
    clic(page, '^Municipio:')
    casilla = boton(page, rf'^{MUNICIPIO} \d+', rol='checkbox')
    n = int(re.search(r'(\d+)$', casilla.get_attribute('aria-label') or casilla.inner_text()).group(1))
    casilla.click(force=True)
    page.wait_for_timeout(500)
    clic(page, r'^Listo( \(\d+\))?$')
    return n


def aplicar_filtros(page):
    return capturar(page, [r'/ejecutivo/dashboard', r'/ejecutivo/solicitudes'],
                    lambda: clic(page, r'^Ver \d+ solicitud', espera=300))


with sync_playwright() as pw:
    browser, page = conectar(pw)
    PAGE = page
    activar_semantica(page)
    page.bring_to_front()
    recuperar(page)
    cdp = browser.new_browser_cdp_session()
    cdp.send('Browser.setDownloadBehavior', {'behavior': 'allowAndName', 'downloadPath': str(DESCARGAS), 'eventsEnabled': True})
    page.on('console', lambda m: consola.append({'tipo': m.type, 'texto': m.text[:200]}) if m.type in ('error', 'warning') else None)
    page.on('pageerror', lambda e: consola.append({'tipo': 'pageerror', 'texto': str(e)[:200]}))
    mon = Monitor(page)
    asegurar_resumen_sin_filtros(page)
    estado = {}

    # E03 Filtro por municipio
    def e03():
        clic(page, r'^Filtros( \d+)?$')
        n = elegir_municipio(page)
        cap = aplicar_filtros(page)
        d, s = cap[r'/ejecutivo/dashboard'], cap[r'/ejecutivo/solicitudes']
        ui = resumen_ui(page, d.json()["total"])
        ok = ('municipio_id' in d.params and d.json()['total'] == n == ui['total'] == s.json()['total'])
        estado['municipio_id'] = d.params.get('municipio_id', [None])[0]
        estado['total_municipio'] = d.json()['total']
        registrar('E03 Filtro por municipio', f'{MUNICIPIO}: total del selector = API tablero = pantalla = API listado',
                  f'selector={n}, API={d.json()["total"]}, pantalla={ui["total"]}, listado={s.json()["total"]}', ok, cap.values())
    paso('E03 Filtro por municipio', 'filtrar por municipio', e03)

    # E02 Tablero sin filtros (al quitar el filtro se recalcula)
    def e02():
        cap = capturar(page, [r'/ejecutivo/dashboard'], lambda: clic(page, '^Quitar filtro$', espera=300))
        d = cap[r'/ejecutivo/dashboard'].json()
        ui = resumen_ui(page, d["total"])
        suma_estatus = d['activas'] + d['resueltas'] + d['no_competencia'] + d['canceladas']
        suma_mun = sum(r['total'] for r in d['municipios'])
        ok = (d['total'] == ui['total'] and int(d['activas']) == ui['activas'] and int(d['resueltas']) == ui['resueltas']
              and suma_estatus == d['total'] and suma_mun == d['total'] and len(d['tendencia']) == 12)
        estado['total'] = d['total']
        registrar('E02 Tablero e indicadores', 'pantalla = API; activas+resueltas+otras = total; suma por municipio = total; 12 meses',
                  f"total={d['total']} (pantalla {ui['total']}), activas={d['activas']}, resueltas={d['resueltas']}, "
                  f"suma estatus={suma_estatus}, suma municipios={suma_mun}, meses={len(d['tendencia'])}", ok, cap.values())
    paso('E02 Tablero e indicadores', 'tablero', e02)

    # E04 Filtro por periodo
    def e04():
        clic(page, r'^Filtros( \d+)?$')
        abrir_periodo(page, INICIO, FIN)
        cap = aplicar_filtros(page)
        d = cap[r'/ejecutivo/dashboard']
        j = d.json()
        ui = resumen_ui(page, j["total"])
        meses = [r['mes'] for r in j['tendencia']]
        ok = (d.params.get('fecha_inicio') == ['2025-01-01'] and d.params.get('fecha_fin') == ['2025-12-31']
              and j['total'] == ui['total'] and j['total'] <= estado.get('total', j['total'])
              and meses[0] == '2025-01' and meses[-1] == '2025-12')
        estado['total_periodo'] = j['total']
        registrar('E04 Filtro por periodo', 'fechas 2025-01-01..2025-12-31 en la petición; tendencia ene–dic 2025; pantalla = API',
                  f"fechas={d.params.get('fecha_inicio')}..{d.params.get('fecha_fin')}, total={j['total']} (pantalla {ui['total']}), "
                  f"tendencia {meses[0]}..{meses[-1]}", ok, cap.values())
    paso('E04 Filtro por periodo', 'periodo', e04)

    # E05 Combinación municipio + periodo
    def e05():
        clic(page, r'^Filtros( \d+)?$')
        elegir_municipio(page)
        cap = aplicar_filtros(page)
        d = cap[r'/ejecutivo/dashboard']
        j = d.json()
        ui = resumen_ui(page, j["total"])
        ok = ({'municipio_id', 'fecha_inicio', 'fecha_fin'} <= set(d.params) and j['total'] == ui['total']
              and j['total'] <= min(estado.get('total_municipio', 10**9), estado.get('total_periodo', 10**9))
              and all(r['nombre'] == MUNICIPIO for r in j['municipios']))
        estado['total_combinado'] = j['total']
        registrar('E05 Combinación de filtros', 'municipio + periodo en la petición; total ≤ cada filtro por separado; solo el municipio elegido',
                  f"total={j['total']} (pantalla {ui['total']}), municipio solo={estado.get('total_municipio')}, "
                  f"periodo solo={estado.get('total_periodo')}, municipios en respuesta={len(j['municipios'])}", ok, cap.values())
    paso('E05 Combinación de filtros', 'combinación', e05)

    # E10/E11 Exportaciones con los filtros combinados
    def exportar(formato):
        clic(page, r'^Exportar (reporte|filtrado)')
        textos = ' '.join(etiquetas(page))
        filtros_visibles = MUNICIPIO in textos and '2025' in textos
        clic(page, '^PDF$' if formato == 'pdf' else '^Excel$', espera=500)
        antes = set(DESCARGAS.iterdir())
        cap = capturar(page, [rf'/ejecutivo/exportar/{formato}'], lambda: clic(page, rf'^Descargar {"PDF" if formato == "pdf" else "Excel"}$', espera=300), timeout=120)
        c = cap[rf'/ejecutivo/exportar/{formato}']
        fin = time.time() + 30
        nuevos = []
        while time.time() < fin and not nuevos:
            page.wait_for_timeout(500)
            nuevos = [p for p in set(DESCARGAS.iterdir()) - antes if not p.name.endswith('.crdownload')]
        descargado = nuevos[0].read_bytes() if nuevos else b''
        if page.get_by_role('button', name=re.compile('^Cerrar$')).count():
            clic(page, '^Cerrar$', espera=600)
        recuperar(page)
        params_ok = {'municipio_id', 'fecha_inicio', 'fecha_fin'} <= set(c.params)
        if formato == 'xlsx':
            book = load_workbook(io.BytesIO(descargado or c.body))
            res = book['Resumen']
            celdas = ' '.join(str(x.value) for row in res for x in row if x.value is not None)
            lab = next(x for row in res for x in row if x.value == 'Solicitudes')
            total_xlsx = res.cell(lab.row + 1, lab.column).value
            ok = (c.status == 200 and descargado == c.body and descargado.startswith(b'PK') and params_ok
                  and filtros_visibles and total_xlsx == estado.get('total_combinado') and MUNICIPIO in celdas
                  and '2025-01-01' in celdas and '2025-12-31' in celdas)
            registrar('E10 Exportación Excel', 'archivo descargado = respuesta; XLSX válido; filtros en la petición y en el reporte; total = tablero filtrado',
                      f"descargado={bool(descargado)} ({len(descargado)//1024} KB), igual a la respuesta={descargado == c.body}, hojas={len(book.sheetnames)}, "
                      f"total en Excel={total_xlsx} (tablero {estado.get('total_combinado')}), municipio y periodo en el reporte={MUNICIPIO in celdas and '2025-01-01' in celdas}",
                      ok, [c])
        else:
            texto = '\n'.join(p.extract_text() for p in PdfReader(io.BytesIO(descargado or c.body)).pages)
            ok = (c.status == 200 and descargado == c.body and descargado.startswith(b'%PDF') and params_ok
                  and filtros_visibles and MUNICIPIO in texto and '2025-01-01 al 2025-12-31' in texto
                  and str(estado.get('total_combinado')) in texto)
            registrar('E11 Exportación PDF', 'archivo descargado = respuesta; PDF válido; municipio, periodo y total del tablero filtrado en el texto',
                      f"descargado={bool(descargado)} ({len(descargado)//1024} KB), igual a la respuesta={descargado == c.body}, "
                      f"municipio en PDF={MUNICIPIO in texto}, periodo en PDF={'2025-01-01 al 2025-12-31' in texto}, total en PDF={str(estado.get('total_combinado')) in texto}",
                      ok, [c])
    paso('E10 Exportación Excel', 'exportar xlsx', lambda: exportar('xlsx'))
    paso('E11 Exportación PDF', 'exportar pdf', lambda: exportar('pdf'))

    # E06 Comparación de periodos (con los filtros vigentes)
    def e06():
        recuperar(page)
        clic(page, '^Resumen$')
        page.mouse.move(720, 500)
        page.mouse.wheel(0, -20000)
        page.wait_for_timeout(600)
        # Si quedó abierta de una corrida anterior, se cierra para medir la apertura desde cero.
        for _ in range(30):
            if page.get_by_role('button', name=re.compile('^(Ocultar comparación|Comparar meses o años)$')).count():
                break
            page.mouse.wheel(0, 600)
            page.wait_for_timeout(500)
        if page.get_by_role('button', name=re.compile('^Ocultar comparación$')).count():
            clic_visible(page, '^Ocultar comparación$')
        cap1 = capturar(page, [r'/ejecutivo/comparacion'], lambda: clic_visible(page, '^Comparar meses o años$', espera=300), timeout=15)
        # La app conserva el modo elegido; Meses -> Años garantiza una consulta nueva por años.
        cap_m = capturar(page, [r'/ejecutivo/comparacion'], lambda: clic_visible(page, '^Meses$', espera=300), timeout=10)
        cap2 = capturar(page, [r'/ejecutivo/comparacion'], lambda: clic_visible(page, '^Años$', espera=300), timeout=20)
        if r'/ejecutivo/comparacion' not in cap1:
            cap1 = cap_m
        c = cap2[r'/ejecutivo/comparacion']
        per = c.json()['periodos']
        variaciones = all(per[i]['variacion']['total']['diferencia'] == per[i]['total'] - per[i - 1]['total'] for i in range(1, len(per)))
        ok = (len(per) >= 2 and per[0]['variacion'] is None and variaciones and 'municipio_id' in c.params
              and len(c.params.get('inicio', [])) == len(per))  # fecha_inicio/fecha_fin, si llegan, los reemplazan los periodos
        registrar('E06 Comparación de periodos', '≥2 periodos; variación = diferencia entre periodos consecutivos; conserva el filtro de municipio',
                  f"meses: {len(cap1[r'/ejecutivo/comparacion'].json()['periodos']) if cap1 else 'sin consulta nueva'} periodos; años: {len(per)} periodos, totales={[p['total'] for p in per]}, "
                  f"variaciones correctas={variaciones}, municipio conservado={'municipio_id' in c.params}",
                  ok, [*cap1.values(), c])
        page.mouse.wheel(0, -20000)
        page.wait_for_timeout(500)
    paso('E06 Comparación de periodos', 'comparación', e06)

    # E07 Navegación del indicador al detalle (sin filtros previos)
    def e07():
        clic(page, r'^Filtros( \d+)?$')
        clic(page, '^Limpiar todo$', espera=600)
        if page.get_by_role('button', name=re.compile('^Quitar todos$')).count():
            clic(page, '^Quitar todos$', espera=600)
        if page.get_by_role('button', name=re.compile(r'^Ver \d+ solicitud')).count():
            aplicar_filtros(page)
        else:
            page.keyboard.press('Escape')
        clic(page, '^Resumen$')
        page.mouse.wheel(0, -20000)
        page.wait_for_timeout(600)
        cap = capturar(page, [r'/ejecutivo/solicitudes', r'/ejecutivo/dashboard'],
                       lambda: boton(page, rf'{MUNICIPIO} \d+', rol='progressbar').click(force=True))
        s, d = cap[r'/ejecutivo/solicitudes'], cap[r'/ejecutivo/dashboard']
        pestaña = any(re.fullmatch(rf'Solicitudes \({estado.get("total_municipio")}\)', t) for t in etiquetas(page))
        ok = ('municipio_id' in s.params and s.params['municipio_id'] == d.params.get('municipio_id')
              and s.json()['total'] == estado.get('total_municipio') and pestaña)
        registrar('E07 Navegación del indicador al detalle', f'al pulsar «{MUNICIPIO}» el listado y el tablero se filtran igual; la pestaña muestra el total',
                  f"listado={s.json()['total']} (esperado {estado.get('total_municipio')}), mismo municipio en ambas peticiones={s.params.get('municipio_id') == d.params.get('municipio_id')}, "
                  f"pestaña «Solicitudes ({estado.get('total_municipio')})»={pestaña}", ok, cap.values())
    paso('E07 Navegación del indicador al detalle', 'drill-down', e07)

    # E08 Listado: paginación y ordenamiento
    def e08():
        cap0 = capturar(page, [r'/ejecutivo/solicitudes'], lambda: clic_visible(page, r'^Solicitudes \(\d+\)$', espera=1500), timeout=8)
        previa = cap0.get(r'/ejecutivo/solicitudes')
        pagina_antes = int(previa.params.get('page', ['0'])[0]) if previa else None
        page.wait_for_timeout(800)
        # La app conserva la página entre filtros: si ya está en la última, «Siguiente» no consulta y se usa «Anterior».
        # La paginación entra al árbol de accesibilidad solo al desplazarse hasta ella.
        alto = page.evaluate('window.innerHeight')
        sig = page.get_by_role('button', name='Siguiente', exact=True)
        for _ in range(15):
            caja = sig.first.bounding_box() if sig.count() else None
            if caja and caja['y'] + caja['height'] <= alto - 10:
                break
            page.mouse.move(720, alto // 2)
            page.mouse.wheel(0, 300)
            page.wait_for_timeout(500)
        direccion_pag = 'Anterior' if (sig.count() and sig.first.is_disabled()) else 'Siguiente'
        cap1 = capturar(page, [r'/ejecutivo/solicitudes'], lambda: clic_visible(page, f'^{direccion_pag}$', espera=300), timeout=15)
        p1 = cap1[r'/ejecutivo/solicitudes']
        if pagina_antes is None:
            pagina_antes = int(p1.params.get('page', ['0'])[0]) + (-1 if direccion_pag == 'Siguiente' else 1)
        # El encabezado está arriba de la tabla: se vuelve al inicio para que su caja coincida con lo pintado.
        page.mouse.move(720, 500)
        page.mouse.wheel(0, -20000)
        page.wait_for_timeout(900)
        cap2 = capturar(page, [r'/ejecutivo/solicitudes'], lambda: clic_visible(page, '^Ordenar por solicitud', rol='columnheader', espera=300))
        o = cap2[r'/ejecutivo/solicitudes']
        ids = [r['solicitud_id'] for r in o.json()['items']]
        asc = o.params.get('direccion') == ['asc']
        ordenado = ids == sorted(ids, reverse=not asc)
        ids_p1 = {r['solicitud_id'] for r in p1.json()['items']}
        pagina = int(p1.params.get('page', ['0'])[0])
        paso_ok = pagina == pagina_antes + (1 if direccion_pag == 'Siguiente' else -1)
        ok = (paso_ok and 0 < len(ids_p1) <= 10 and p1.json()['total'] == estado.get('total_municipio')
              and o.params.get('orden') == ['solicitud'] and ordenado)
        estado['folio'] = ids[0] if ids else None
        registrar('E08 Listado, paginación y ordenamiento', 'cambio de página de uno en uno con ≤10 filas del mismo total; orden por folio aplicado en el servidor',
                  f"«{direccion_pag}»: página {pagina_antes}→{pagina}, filas={len(ids_p1)}, total={p1.json()['total']}, orden={o.params.get('orden')} {o.params.get('direccion')}, "
                  f"folios ordenados={ordenado}", ok, [*cap0.values(), p1, o])
    paso('E08 Listado, paginación y ordenamiento', 'listado', e08)

    # E09 Búsqueda y apertura de una solicitud existente
    def e09():
        folio = estado.get('folio')
        if not folio:
            registrar('E09 Búsqueda y apertura de una solicitud', 'buscar y abrir', 'sin folio del listado', None)
            return
        page.mouse.move(720, 500)
        page.mouse.wheel(0, -20000)
        page.wait_for_timeout(800)
        # Flutter fusiona el buscador con su contenedor: se enfoca el <input> por programación.
        page.locator('input').first.focus()
        page.wait_for_timeout(500)
        page.keyboard.press('Control+A')
        cap1 = capturar(page, [r'/ejecutivo/solicitudes/sugerencias', r'/ejecutivo/solicitudes'],
                        lambda: page.keyboard.type(f'#{folio}', delay=80), timeout=20)
        sug_c, lista = cap1.get(r'/ejecutivo/solicitudes/sugerencias'), cap1.get(r'/ejecutivo/solicitudes')
        en_sug = sug_c is not None and folio in [r['solicitud_id'] for r in sug_c.json()['solicitudes']]
        en_lista = lista is not None and lista.params.get('q') == [f'#{folio}'] and folio in [r['solicitud_id'] for r in lista.json()['items']]
        # Apertura: la primera fila visible con folio (una solicitud existente del listado),
        # después de que la tabla termine de actualizarse con la búsqueda.
        page.wait_for_timeout(2500)
        # La tabla se desplaza en horizontal: se usa la celda del folio, que siempre está a la vista.
        filas = page.get_by_role('cell', name=re.compile(r'Solicitud #\d+'))
        abrir = None
        for i in range(min(filas.count(), 12)):
            caja = filas.nth(i).bounding_box()
            if caja and 60 <= caja['y'] <= page.evaluate('window.innerHeight') - 40:
                abrir = int(re.search(r'Solicitud #(\d+)', filas.nth(i).get_attribute('aria-label') or filas.nth(i).inner_text()).group(1))
                break
        cap3 = {}
        for _ in range(2):
            cap3 = capturar(page, [rf'/ejecutivo/solicitudes/{abrir}'],
                            lambda: clic_visible(page, rf'Solicitud #{abrir}\b', rol='cell', espera=300), timeout=12)
            if cap3:
                break
            page.wait_for_timeout(1500)
        det = cap3[rf'/ejecutivo/solicitudes/{abrir}']
        dj = det.json()
        pantalla_detalle = False
        for _ in range(20):  # espera a que Flutter muestre la pantalla de detalle (máx. 10 s)
            if page.get_by_role('button', name=re.compile('^Volver$')).count():
                pantalla_detalle = True
                break
            page.wait_for_timeout(500)
        ok = (en_sug and det.status == 200 and dj['solicitud_id'] == abrir
              and dj['folio'] == f'Solicitud #{abrir}' and pantalla_detalle)
        registrar('E09 Búsqueda y apertura de una solicitud', f'buscar «#{folio}» la sugiere y filtra el listado; abrir una fila trae su detalle',
                  f"en sugerencias={en_sug}, en listado filtrado={en_lista}, abierta=Solicitud #{abrir}, detalle folio={dj['folio']}, "
                  f"campos={len(dj)}, pantalla de detalle={pantalla_detalle}", ok, [*cap1.values(), det])
        clic(page, '^Volver$', espera=800)
    paso('E09 Búsqueda y apertura de una solicitud', 'búsqueda', e09)

    # Paridad HTTP con el monolito, con el token de la sesión solo en memoria
    token = mon.token()
    paridad = []
    if token:
        with httpx.Client(timeout=120) as http:
            for c in capturas:
                if c.metodo != 'GET' or not c.path.startswith('/ejecutivo/') or c.status != 200:
                    continue
                q = urlsplit(c.url).query
                r = http.get(f'{MONOLITO}{c.path}' + (f'?{q}' if q else ''), headers={'Authorization': f'Bearer {token}'})
                fila = {'ruta': c.path, 'parametros': sorted(c.params), 'codigo_ms': c.status, 'codigo_monolito': r.status_code}
                if c.path.endswith('/xlsx'):
                    def celdas(b):
                        bk = load_workbook(io.BytesIO(b))
                        return {(s.title, x.coordinate): x.value for s in bk for row in s for x in row if x.value is not None and x.coordinate != 'B6'}
                    fila['igual'] = r.status_code == c.status and celdas(r.content) == celdas(c.body)
                    fila['excluido'] = 'celda B6 de cada hoja (fecha y hora de generación)'
                elif c.path.endswith('/pdf'):
                    def texto(b):
                        t = '\n'.join(p.extract_text() for p in PdfReader(io.BytesIO(b)).pages)
                        return re.sub(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC', '<generado>', t)
                    fila['igual'] = r.status_code == c.status and texto(r.content) == texto(c.body)
                    fila['excluido'] = 'fecha y hora de generación'
                else:
                    fila['igual'] = r.status_code == c.status and r.json() == c.json()
                paridad.append(fila)
        token = None
    else:
        paridad = None

    # E12 Cierre de sesión y revocación
    def e12():
        tok = mon.token()
        clic(page, '^Mi perfil$')
        cap = capturar(page, [r'/auth/logout'], lambda: clic(page, '^Cerrar sesión$', espera=500), metodo='POST', timeout=10)
        if r'/auth/logout' not in cap and page.get_by_role('button', name=re.compile('^Cerrar sesión$')).count():
            cap = capturar(page, [r'/auth/logout'], lambda: clic(page, '^Cerrar sesión$', espera=500), metodo='POST', timeout=10)
        lo = cap.get(r'/auth/logout')
        with httpx.Client(timeout=30) as http:
            me = http.get(f'{GATEWAY}/auth/me', headers={'Authorization': f'Bearer {tok}'}).status_code
            dash = http.get(f'{GATEWAY}/ejecutivo/dashboard', headers={'Authorization': f'Bearer {tok}'})
        tok = None
        page.wait_for_timeout(1500)
        pantalla_login = any(t == 'Iniciar sesión' for t in etiquetas(page))
        ok = lo is not None and lo.status == 200 and me == 401 and dash.status_code == 401 and pantalla_login
        registrar('E12 Cierre de sesión y revocación', 'POST /auth/logout 200; el mismo token da 401 en el núcleo y en indicadores; vuelve al login',
                  f"logout={lo.status if lo else 'no enviado'}, /auth/me con el token={me}, /ejecutivo/dashboard con el token={dash.status_code} "
                  f"(servicio {dash.headers.get('x-sgsc-service')}), pantalla de login={pantalla_login}", ok, [lo] if lo else [])
    if os.environ.get('SGSC_E2E_SIN_LOGOUT') == '1':
        registrar('E12 Cierre de sesión y revocación', 'logout', 'omitida en esta corrida de depuración', None)
    else:
        paso('E12 Cierre de sesión y revocación', 'logout', e12)

    salida = {'resultados': resultados, 'paridad_monolito': paridad, 'consola_navegador': consola,
              'peticiones_api': [c.evidencia() for c in capturas]}
    SALIDA.write_text(json.dumps(salida, ensure_ascii=False, indent=1, default=str), encoding='utf-8')
    print('PARIDAD:', 'no disponible' if paridad is None else f"{sum(f['igual'] for f in paridad)}/{len(paridad)} iguales")
    print('CONSOLA:', len(consola), 'errores/avisos')
