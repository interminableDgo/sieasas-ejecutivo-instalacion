"""R01: registro de una solicitud SINTÉTICA desde el formulario Flutter (Chrome real) y prueba de idempotencia.

Uso: r01_registro.py <salida.json> <hasta_paso 1..8> [enviar]
- Sin «enviar» solo llena hasta el paso indicado y se detiene: no hay ninguna escritura de negocio.
- Con «enviar» pulsa «Registrar solicitud» (POST Flutter -> Nginx -> registro -> Aiven) y después
  reenvía EXACTAMENTE el mismo cuerpo (misma clave de idempotencia) por el gateway, con el token
  de la sesión solo en memoria. Nunca imprime ni guarda el token.
Datos 100 % sintéticos autorizados por el usuario (sin CURP, teléfono 0000000000).
"""
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from playwright.sync_api import sync_playwright

from e2e_comun import Monitor, activar_semantica, conectar

SALIDA, HASTA = Path(sys.argv[1]), int(sys.argv[2])
ENVIAR = 'enviar' in sys.argv
GATEWAY = 'http://localhost:8080'
FECHA = '01/01/2000'
DESCRIPCION = ('[PRUEBA AUTOMATIZADA SGSC – NO ATENDER] Validación técnica del microservicio Registro '
               '(Docker + gateway). Registro sintético; no corresponde a ninguna persona.')
OBSERVACIONES = 'Registro sintético de pruebas E2E del 17/11/2026; no corresponde a ninguna persona.'

_HIJOS = os.environ.get('SGSC_HIJOS', 'No')
HIJOS = ([('respuesta', '¿Tiene hijos?', 'No')] if _HIJOS == 'No'
         else [('respuesta', '¿Tiene hijos?', 'Sí'), ('texto', '¿Cuántos hijos tiene?', _HIJOS)])

PASOS = {
    1: [('texto', 'Nombre(s)', 'PRUEBA E2E SGSC'), ('texto', 'Apellidos', 'REGISTRO SINTETICO 17NOV2026'),
        ('fecha', 'Fecha de nacimiento', FECHA), ('lista', 'Género', 'Prefiere no especificar'),
        ('lista', 'Estado de nacimiento', 'Nuevo León'), ('lista', 'Municipio de nacimiento', 'Monterrey')],
    2: [('lista', 'Municipio de domicilio', 'Monterrey'), ('lista', 'Colonia', 'Centro'),
        ('texto', 'Calle', 'CALLE DE PRUEBA SGSC'), ('texto', 'Número exterior / interior', '0'),
        ('texto', 'Años de residencia', '0')],
    # «¿Tiene hijos?» (solo interfaz): SGSC_HIJOS=No (por omisión) o una cantidad, que implica Sí.
    3: [('lista', '¿Con quién vive?', 'Solo(a)'), *HIJOS,
        ('lista', 'Seguridad social', 'Ninguno'), ('lista', 'Grupo vulnerable', 'No')],
    4: [('texto', 'Nombre(s)', 'PRUEBA E2E SGSC'), ('texto', 'Apellidos', 'SOLICITANTE SINTETICO'),
        ('lista', 'Parentesco con el beneficiario', 'El mismo / Ella misma'), ('fecha', 'Fecha de nacimiento', FECHA)],
    5: [('interruptor', 'Vive en el mismo domicilio que el beneficiario', True), ('texto', 'Teléfono', '0000000000')],
    6: [('lista', 'Tipo de apoyo', 'Peticiones Administrativas'), ('lista', 'Origen de la solicitud', 'Otro'),
        ('texto', 'Detalles del envío (opcional)', 'Prueba técnica de microservicios'),
        ('lista', 'Canal de recepción', 'No especificado'), ('lista', 'Unidad tratante', 'No especificado')],
    7: [('texto', 'Descripción de la solicitud', DESCRIPCION), ('texto', 'Observaciones (opcional)', OBSERVACIONES)],
}

NODOS = '''() => [...document.querySelectorAll('flt-semantics, input, textarea')].map((e, i) => {
    const r = e.getBoundingClientRect();
    return {i, tag: e.tagName.toLowerCase(), role: e.getAttribute('role') || '',
            label: (e.getAttribute('aria-label') || e.innerText || '').replace(/\\s+/g, ' ').trim(),
            ro: e.readOnly === true, x: r.x, y: r.y, w: r.width, h: r.height};
  }).filter(o => o.w > 0 && o.h > 0)'''


def alto(page):
    return page.evaluate('window.innerHeight')


def desplazar(page, dy):
    page.mouse.move(700, alto(page) // 2)
    page.mouse.wheel(0, dy)
    page.wait_for_timeout(450)


def etiqueta(page, texto):
    """Nodo de la etiqueta visible del campo (coincidencia exacta o por prefijo), desplazando si hace falta."""
    for intento in range(24):
        nodos = page.evaluate(NODOS)
        cand = [n for n in nodos if n['tag'] == 'flt-semantics' and n['role'] == '' and n['h'] < 40
                and (n['label'] == texto or n['label'].startswith(texto))]
        visibles = [n for n in cand if 70 <= n['y'] <= alto(page) - 140]
        if visibles:
            return visibles[0], nodos
        desplazar(page, 260 if not cand or cand[0]['y'] > alto(page) - 140 else -260)
    raise RuntimeError(f'etiqueta no encontrada: {texto}')


def debajo(nodos, lab, filtro, max_dist=110):
    opciones = [n for n in nodos if filtro(n) and lab['y'] < n['y'] <= lab['y'] + lab['h'] + max_dist]
    if not opciones:
        raise RuntimeError(f"sin control bajo «{lab['label']}»")
    return min(opciones, key=lambda n: n['y'])


def clic_centro(page, n, dx=None):
    page.mouse.click(n['x'] + (dx if dx is not None else n['w'] / 2), n['y'] + n['h'] / 2)


def escribir(page, label, valor):
    lab, nodos = etiqueta(page, label)
    campo = debajo(nodos, lab, lambda n: n['tag'] in ('input', 'textarea'))
    loc = page.locator('input, textarea').nth([n for n in nodos if n['tag'] in ('input', 'textarea')].index(campo))
    loc.focus()
    page.wait_for_timeout(250)
    page.keyboard.press('Control+A')
    page.keyboard.type(valor, delay=15)
    page.wait_for_timeout(300)


def elegir(page, label, opcion):
    lab, nodos = etiqueta(page, label)
    boton = debajo(nodos, lab, lambda n: n['role'] == 'button')
    clic_centro(page, boton, dx=40)
    fin = time.time() + 20
    while time.time() < fin:
        page.wait_for_timeout(600)
        items = [n for n in page.evaluate(NODOS) if n['role'] == 'menuitem']
        objetivo = [n for n in items if n['label'] == opcion or n['label'].startswith(opcion + ' ')]
        if objetivo and 0 <= objetivo[0]['y'] <= alto(page) - 20:
            clic_centro(page, objetivo[0])
            page.wait_for_timeout(1500)
            return
        if items:  # el menú ya se abrió: desplazar dentro de él
            menu = items[len(items) // 2]
            page.mouse.move(menu['x'] + menu['w'] / 2, menu['y'] + menu['h'] / 2)
            page.mouse.wheel(0, 240)
    raise RuntimeError(f'opción no encontrada: {label} = {opcion}')


def fecha(page, label, valor):
    lab, nodos = etiqueta(page, label)
    campo = debajo(nodos, lab, lambda n: n['tag'] == 'input')
    clic_centro(page, campo, dx=60)
    page.wait_for_timeout(2500)
    page.get_by_role('button', name='Cambiar a modo de entrada').first.click(force=True)
    page.wait_for_timeout(2000)
    page.locator('input[aria-label="Ingresar fecha"]').first.focus()
    page.keyboard.press('Control+A')
    page.keyboard.type(valor, delay=40)
    page.wait_for_timeout(500)
    aceptar = page.get_by_role('button', name=re.compile('^(aceptar|ok)$', re.I))
    if aceptar.count():
        b = aceptar.first.bounding_box()
        page.mouse.click(b['x'] + b['width'] / 2, b['y'] + b['height'] / 2)
    else:
        page.keyboard.press('Enter')
    page.wait_for_timeout(1500)


def respuesta(page, label, opcion):
    """Pregunta de opción (botones segmentados Sí/No) bajo la etiqueta indicada."""
    lab, nodos = etiqueta(page, label)
    boton = debajo(nodos, lab, lambda n: n['label'] == opcion and n['role'] in ('button', 'radio', 'checkbox', ''))
    clic_centro(page, boton)
    page.wait_for_timeout(1200)


def interruptor(page, label, valor):
    loc = page.get_by_role('switch', name=label)
    actual = loc.first.get_attribute('aria-checked') == 'true'
    if actual != valor:
        b = loc.first.bounding_box()
        page.mouse.click(b['x'] + b['width'] / 2, b['y'] + b['height'] / 2)
        page.wait_for_timeout(1200)


def paso_actual(page):
    for n in page.evaluate(NODOS):
        m = re.match(r'Paso (\d) de 8', n['label'])
        if m:
            return int(m.group(1))
    return None


def boton_inferior(page, nombre):
    for _ in range(20):
        loc = page.get_by_role('button', name=nombre, exact=True)
        if loc.count():
            b = loc.first.bounding_box()
            if b and b['y'] + b['height'] <= alto(page) - 5:
                page.mouse.click(b['x'] + b['width'] / 2, b['y'] + b['height'] / 2)
                return
        desplazar(page, 400)
    raise RuntimeError(f'botón no visible: {nombre}')


with sync_playwright() as pw:
    browser, page = conectar(pw)
    activar_semantica(page)
    page.bring_to_front()
    mon = Monitor(page)
    registro = {'pasos': [], 'peticiones': []}
    # Diálogos abiertos (p. ej. un selector de fecha) se cierran con «Cancelar».
    for _ in range(3):
        cancelar = page.get_by_role('button', name=re.compile('^cancelar$', re.I))
        if not cancelar.count():
            break
        b = cancelar.first.bounding_box()
        page.mouse.click(b['x'] + b['width'] / 2, b['y'] + b['height'] / 2)
        page.wait_for_timeout(1000)
    # Formulario nuevo: si hay uno abierto se vuelve al tablero (sin enviar nada) y se abre otro.
    for _ in range(3):
        if page.get_by_role('button', name='Volver', exact=True).count():
            page.get_by_role('button', name='Volver', exact=True).first.click(force=True)
            page.wait_for_timeout(1200)
            for nombre in ('Descartar', 'Salir', 'Sí, salir'):
                if page.get_by_role('button', name=nombre, exact=True).count():
                    page.get_by_role('button', name=nombre, exact=True).first.click(force=True)
                    page.wait_for_timeout(800)
    page.mouse.wheel(0, -20000)
    page.wait_for_timeout(600)
    page.get_by_role('button', name='Nueva solicitud', exact=True).first.click(force=True)
    page.wait_for_timeout(2000)

    for numero in range(1, min(HASTA, 7) + 1):
        assert paso_actual(page) == numero, f'se esperaba el paso {numero}, la pantalla muestra {paso_actual(page)}'
        for tipo, label, valor in PASOS[numero]:
            {'texto': escribir, 'lista': elegir, 'fecha': fecha, 'interruptor': interruptor,
             'respuesta': respuesta}[tipo](page, label, valor)
        page.mouse.wheel(0, -20000)
        boton_inferior(page, 'Continuar')
        page.wait_for_timeout(1800)
        llego = paso_actual(page)
        registro['pasos'].append({'paso': numero, 'siguiente': llego})
        print(f'paso {numero} completado -> pantalla en paso {llego}', flush=True)
        if llego != numero + 1:
            raise RuntimeError(f'el formulario no avanzó del paso {numero} (validación pendiente)')

    if HASTA >= 8:
        textos = [n['label'] for n in page.evaluate(NODOS) if n['tag'] == 'flt-semantics' and n['label']]
        registro['revision_visible'] = [t for t in textos if len(t) < 120][:60]
        print('Revisión (paso 8):', ' | '.join(registro['revision_visible'][:40]), flush=True)

    if ENVIAR and HASTA >= 8:
        capturado = {}

        def on(response):
            if urlsplit(response.url).path == '/ejecutivo/solicitudes' and response.request.method == 'POST':
                capturado['r'] = response
                capturado['body'] = response.request.post_data
        page.on('response', on)
        boton_inferior(page, 'Registrar solicitud')
        fin = time.time() + 60
        while 'r' not in capturado and time.time() < fin:
            page.wait_for_timeout(300)
        page.remove_listener('response', on)
        r = capturado['r']
        cuerpo = json.loads(capturado['body'])
        t = r.request.timing
        primero = {'codigo': r.status, 'servicio': r.headers.get('x-sgsc-service'), 'json': r.json(),
                   'ms': round(t['responseEnd']) if t and t.get('responseEnd', -1) >= 0 else None}
        page.wait_for_timeout(3000)
        token = mon.token()
        with httpx.Client(timeout=60) as http:
            r2 = http.post(f'{GATEWAY}/ejecutivo/solicitudes', json=cuerpo, headers={'Authorization': f'Bearer {token}'})
        token = None
        segundo = {'codigo': r2.status_code, 'servicio': r2.headers.get('x-sgsc-service'), 'json': r2.json(),
                   'ms': round(r2.elapsed.total_seconds() * 1000)}
        registro.update({
            'clave_idempotencia': cuerpo['idempotencia'],
            'campos_enviados': sorted(cuerpo),
            'beneficiario_enviado': {k: v for k, v in (cuerpo.get('beneficiario') or {}).items()},
            'solicitante_enviado': {k: v for k, v in (cuerpo.get('solicitante') or {}).items()},
            'primer_envio_flutter': primero, 'segundo_envio_gateway_misma_clave': segundo,
            'mismo_folio': primero['json'].get('folio') == segundo['json'].get('folio'),
            'pantalla_tras_envio': [n['label'] for n in page.evaluate(NODOS) if n['label'] and len(n['label']) < 90][:12],
        })
        print('PRIMER ENVÍO (Flutter):', primero, flush=True)
        print('SEGUNDO ENVÍO (gateway, misma clave):', segundo, flush=True)

    registro['peticiones'] = [{k: r[k] for k in ('metodo', 'ruta', 'codigo', 'servicio', 'ms', 'consulta')} for r in mon.registros]
    SALIDA.write_text(json.dumps(registro, ensure_ascii=False, indent=1, default=str), encoding='utf-8')
    print('Peticiones API:', [(r['metodo'], r['ruta'], r['codigo'], r['servicio']) for r in mon.registros], flush=True)
