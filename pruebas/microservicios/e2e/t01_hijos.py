"""T01: «¿Tiene hijos?» y CURP en el formulario Flutter (Chrome real), SIN enviar.

Uso: t01_hijos.py <salida.json> [carpeta_capturas]
Requiere una sesión ya iniciada en el Chrome visible (CDP 127.0.0.1:9223) con la app en
http://localhost:8080. Llena datos sintéticos hasta la pantalla de revisión y se detiene ahí.
Salvaguarda: cualquier POST a /ejecutivo/solicitudes se aborta en el navegador, así que no puede
haber escritura de negocio aunque se pulsara «Registrar solicitud». No imprime ni guarda tokens.
"""
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

from e2e_comun import Monitor, activar_semantica, conectar

SALIDA = Path(sys.argv[1])
CAPTURAS = Path(sys.argv[2]) if len(sys.argv) > 2 else None
FECHA = '01/01/2000'
NODOS = '''() => { const campos = [...document.querySelectorAll('input, textarea')];
  return [...document.querySelectorAll('flt-semantics, input, textarea')].map((e, i) => {
    const r = e.getBoundingClientRect();
    return {i, k: campos.indexOf(e), tag: e.tagName.toLowerCase(), role: e.getAttribute('role') || '',
            label: (e.getAttribute('aria-label') || e.innerText || '').replace(/\\s+/g, ' ').trim(),
            value: e.value === undefined ? null : e.value,
            sel: e.getAttribute('aria-selected') || e.getAttribute('aria-checked') || e.getAttribute('aria-pressed') || '',
            x: r.x, y: r.y, w: r.width, h: r.height};
  }).filter(o => o.w > 0 && o.h > 0); }'''

PASO1 = [('texto', 'Nombre(s)', 'PRUEBA E2E SGSC'), ('texto', 'Apellidos', 'HIJOS SINTETICO 17NOV2026'),
         ('fecha', 'Fecha de nacimiento', FECHA), ('lista', 'Género', 'Prefiere no especificar'),
         ('lista', 'Estado de nacimiento', 'Nuevo León'), ('lista', 'Municipio de nacimiento', 'Monterrey')]
PASO2 = [('lista', 'Municipio de domicilio', 'Monterrey'), ('lista', 'Colonia', 'Centro'),
         ('texto', 'Calle', 'CALLE DE PRUEBA SGSC'), ('texto', 'Número exterior / interior', '0'),
         ('texto', 'Años de residencia', '0')]
PASO3_SIN_HIJOS = [('lista', '¿Con quién vive?', 'Solo(a)'), ('lista', 'Seguridad social', 'Ninguno'),
                   ('lista', 'Grupo vulnerable', 'No')]
PASOS_4_A_7 = {
    4: [('texto', 'Nombre(s)', 'PRUEBA E2E SGSC'), ('texto', 'Apellidos', 'SOLICITANTE SINTETICO'),
        ('lista', 'Parentesco con el beneficiario', 'El mismo / Ella misma'), ('fecha', 'Fecha de nacimiento', FECHA)],
    5: [('interruptor', 'Vive en el mismo domicilio que el beneficiario', True), ('texto', 'Teléfono', '0000000000')],
    6: [('lista', 'Tipo de apoyo', 'Peticiones Administrativas'), ('lista', 'Origen de la solicitud', 'Otro'),
        ('lista', 'Canal de recepción', 'No especificado'), ('lista', 'Unidad tratante', 'No especificado')],
    7: [('texto', 'Descripción de la solicitud', '[PRUEBA AUTOMATIZADA SGSC – NO ENVIAR] Validación de «¿Tiene hijos?».')],
}

resultados = []


def comprobar(nombre, condicion, detalle=''):
    resultados.append({'comprobacion': nombre, 'aprobada': bool(condicion), 'detalle': detalle})
    print(('OK    ' if condicion else 'FALLA ') + nombre + (f' — {detalle}' if detalle else ''), flush=True)


def alto(page):
    return page.evaluate('window.innerHeight')


def desplazar(page, dy):
    page.mouse.move(page.evaluate('window.innerWidth') // 2, alto(page) // 2)  # dentro de la columna de la app
    page.mouse.wheel(0, dy)
    page.wait_for_timeout(450)


def arriba(page):
    desplazar(page, -20000)
    page.wait_for_timeout(300)


def textos(page):
    """Todas las etiquetas del formulario, recorriéndolo de arriba abajo (Flutter solo expone lo cercano)."""
    arriba(page)
    vistos, orden = set(), []
    for _ in range(30):
        antes = len(orden)
        for n in page.evaluate(NODOS):
            if n['tag'] == 'flt-semantics' and n['label'] and (n['label'], round(n['y'] + page.evaluate('window.scrollY'))) not in vistos:
                vistos.add((n['label'], round(n['y'] + page.evaluate('window.scrollY'))))
                if not orden or orden[-1] != n['label']:
                    orden.append(n['label'])
        desplazar(page, 350)
        if len(orden) == antes and _ > 3:
            break
    arriba(page)
    return orden


def contiene(lista, texto):
    return any(texto in t for t in lista)


def etiqueta(page, texto):
    for _ in range(24):
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


def campo(page, label):
    lab, nodos = etiqueta(page, label)
    c = debajo(nodos, lab, lambda n: n['tag'] in ('input', 'textarea'))
    return page.locator('input, textarea').nth(c['k']), c


def escribir(page, label, valor):
    loc, c = campo(page, label)
    clic_centro(page, c)
    page.wait_for_timeout(300)
    page.keyboard.press('Control+A')
    if valor:
        page.keyboard.type(valor, delay=15)
    else:
        page.keyboard.press('Delete')
    page.wait_for_timeout(400)


def valor_campo(page, label):
    """Flutter web solo refleja el texto en el <input> mientras el campo tiene el foco."""
    _, c = campo(page, label)
    clic_centro(page, c)
    page.wait_for_timeout(400)
    valor = page.evaluate('document.activeElement && document.activeElement.value')
    page.keyboard.press('Tab')
    page.wait_for_timeout(300)
    return valor


def elegir(page, label, opcion):
    lab, nodos = etiqueta(page, label)
    boton = debajo(nodos, lab, lambda n: n['role'] == 'button')
    clic_centro(page, boton, dx=40)
    fin = time.time() + 20
    while time.time() < fin:
        page.wait_for_timeout(600)
        items = [n for n in page.evaluate(NODOS) if n['role'] == 'menuitem']
        objetivo = [n for n in items if n['label'] == opcion or n['label'].startswith(opcion + ' ')]
        if objetivo and 0 <= objetivo[0]['y'] and objetivo[0]['y'] + objetivo[0]['h'] <= alto(page) - 5:
            clic_centro(page, objetivo[0])
            page.wait_for_timeout(1500)
            return
        if items:
            menu = items[len(items) // 2]
            page.mouse.move(menu['x'] + menu['w'] / 2, menu['y'] + menu['h'] / 2)
            page.mouse.wheel(0, 240)
    raise RuntimeError(f'opción no encontrada: {label} = {opcion}')


def fecha(page, label, valor):
    lab, nodos = etiqueta(page, label)
    c = debajo(nodos, lab, lambda n: n['tag'] == 'input')
    clic_centro(page, c, dx=60)
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


def respuesta(page, opcion):
    lab, nodos = etiqueta(page, '¿Tiene hijos?')
    boton = debajo(nodos, lab, lambda n: n['label'] == opcion and n['role'] in ('button', 'radio', 'checkbox', ''))
    clic_centro(page, boton)
    page.wait_for_timeout(1200)


def interruptor(page, label, valor):
    loc = page.get_by_role('switch', name=label)
    if (loc.first.get_attribute('aria-checked') == 'true') != valor:
        b = loc.first.bounding_box()
        page.mouse.click(b['x'] + b['width'] / 2, b['y'] + b['height'] / 2)
        page.wait_for_timeout(1200)


def llenar(page, pasos):
    for tipo, label, valor in pasos:
        {'texto': escribir, 'lista': elegir, 'fecha': fecha, 'interruptor': interruptor}[tipo](page, label, valor)


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


def continuar(page):
    arriba(page)
    boton_inferior(page, 'Continuar')
    page.wait_for_timeout(1800)
    return paso_actual(page)


def anterior(page):
    arriba(page)
    boton_inferior(page, 'Paso anterior')
    page.wait_for_timeout(1500)
    return paso_actual(page)


def captura(page, nombre):
    if CAPTURAS:
        CAPTURAS.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(CAPTURAS / f'{nombre}.png'))


def revision(page):
    """Pares etiqueta → valor de la tarjeta Beneficiario en la pantalla de revisión."""
    t = textos(page)
    return t


with sync_playwright() as pw:
    browser, page = conectar(pw)
    activar_semantica(page)
    page.bring_to_front()
    mon = Monitor(page)
    bloqueados = []

    def bloquear(route):
        if route.request.method == 'POST':
            bloqueados.append(urlsplit(route.request.url).path)
            route.abort()
        else:
            route.continue_()
    page.route('**/ejecutivo/solicitudes', bloquear)

    for _ in range(3):  # cierra diálogos abiertos y vuelve al tablero sin enviar nada
        cancelar = page.get_by_role('button', name=re.compile('^cancelar$', re.I))
        if cancelar.count():
            cancelar.first.click(force=True)
            page.wait_for_timeout(800)
        if page.get_by_role('button', name='Volver', exact=True).count():
            page.get_by_role('button', name='Volver', exact=True).first.click(force=True)
            page.wait_for_timeout(1200)
            for nombre in ('Descartar', 'Salir', 'Sí, salir'):
                if page.get_by_role('button', name=nombre, exact=True).count():
                    page.get_by_role('button', name=nombre, exact=True).first.click(force=True)
                    page.wait_for_timeout(800)
    arriba(page)
    page.get_by_role('button', name='Nueva solicitud', exact=True).first.click(force=True)
    page.wait_for_timeout(2500)
    comprobar('Abre el formulario en el paso 1', paso_actual(page) == 1, f'paso {paso_actual(page)}')

    # --- CURP (comportamiento existente: opcional, valida formato mientras se escribe, bloquea si es inválida)
    llenar(page, PASO1)
    escribir(page, 'CURP (opcional)', '1234')
    t = textos(page)
    comprobar('CURP «1234»: muestra el error de iniciales', contiene(t, 'Revisa las iniciales'))
    comprobar('CURP inválida impide avanzar', continuar(page) == 1)
    escribir(page, 'CURP (opcional)', 'goma')
    mostrado = valor_campo(page, 'CURP (opcional)')
    t = textos(page)
    comprobar('CURP incompleta («goma»): pide 18 caracteres', contiene(t, 'La CURP debe tener 18 caracteres (llevas 4)'),
              f'el campo muestra «{mostrado}»')
    comprobar('CURP incompleta impide avanzar', continuar(page) == 1)
    escribir(page, 'CURP (opcional)', '')
    t = textos(page)
    comprobar('CURP vacía: sin mensaje de error', not contiene(t, 'La CURP debe') and not contiene(t, 'Revisa las iniciales'))
    comprobar('CURP vacía permite avanzar (es opcional)', continuar(page) == 2)
    captura(page, '01_paso2')

    llenar(page, PASO2)
    comprobar('Paso 2 completo avanza al paso 3', continuar(page) == 3)

    # --- ¿Tiene hijos?
    llenar(page, PASO3_SIN_HIJOS)
    t = textos(page)
    comprobar('Al abrir el paso 3 no hay respuesta y la cantidad está oculta',
              contiene(t, '¿Tiene hijos?') and not contiene(t, '¿Cuántos hijos tiene?'))
    comprobar('Sin elegir Sí o No no puede avanzar', continuar(page) == 3)
    t = textos(page)
    comprobar('Muestra «Indica si tiene hijos.»', contiene(t, 'Indica si tiene hijos.'))
    captura(page, '02_sin_respuesta')

    respuesta(page, 'No')
    t = textos(page)
    comprobar('No: se ocultan la cantidad y «Algún hijo tiene seguridad social»',
              not contiene(t, '¿Cuántos hijos tiene?') and not contiene(t, 'Algún hijo tiene seguridad social'))

    respuesta(page, 'Sí')
    t = textos(page)
    comprobar('Sí: aparecen la cantidad y la casilla de seguridad social',
              contiene(t, '¿Cuántos hijos tiene?') and contiene(t, 'Algún hijo tiene seguridad social'))
    vacio = valor_campo(page, '¿Cuántos hijos tiene?')
    comprobar('No → Sí: la cantidad aparece vacía (el 0 de «No» no se muestra)', vacio == '', f'valor «{vacio}»')
    comprobar('Sí con cantidad vacía no puede avanzar', continuar(page) == 3)
    t = textos(page)
    comprobar('Sí vacío: muestra «Completa este campo.»', contiene(t, 'Completa este campo.'))

    escribir(page, '¿Cuántos hijos tiene?', '0')
    comprobar('Sí con 0 no puede avanzar', continuar(page) == 3)
    t = textos(page)
    comprobar('Sí con 0: muestra «Ingresa un número entero entre 1 y 100.»', contiene(t, 'Ingresa un número entero entre 1 y 100.'))
    captura(page, '03_si_cero')

    escribir(page, '¿Cuántos hijos tiene?', '2')
    comprobar('Sí con 2 puede continuar al paso 4', continuar(page) == 4)
    comprobar('Paso anterior regresa al paso 3', anterior(page) == 3)
    conservado = valor_campo(page, '¿Cuántos hijos tiene?')
    comprobar('Al regresar se conserva Sí con 2', conservado == '2', f'valor «{conservado}»')

    respuesta(page, 'No')
    t = textos(page)
    comprobar('Sí → No: la cantidad se oculta', not contiene(t, '¿Cuántos hijos tiene?'))
    respuesta(page, 'Sí')
    tras = valor_campo(page, '¿Cuántos hijos tiene?')
    comprobar('Sí → No → Sí: el 2 anterior se descartó (No fijó 0 y Sí vuelve a pedir la cantidad)', tras == '', f'valor «{tras}»')
    respuesta(page, 'No')
    comprobar('Con No puede continuar al paso 4', continuar(page) == 4)

    # --- Resto del formulario hasta la revisión, sin enviar
    for numero in (4, 5, 6, 7):
        llenar(page, PASOS_4_A_7[numero])
        llego = continuar(page)
        comprobar(f'Paso {numero} completo avanza al paso {numero + 1}', llego == numero + 1, f'paso {llego}')
    rev_no = revision(page)
    i = rev_no.index('¿Tiene hijos?') if '¿Tiene hijos?' in rev_no else -1
    comprobar('Revisión con No: «¿Tiene hijos?» = No y sin cantidad',
              i >= 0 and rev_no[i + 1] == 'No' and not contiene(rev_no, '¿Cuántos hijos tiene?'),
              ' | '.join(rev_no[max(i - 2, 0):i + 3]) if i >= 0 else 'etiqueta ausente')
    i = rev_no.index('CURP (opcional)') if 'CURP (opcional)' in rev_no else -1
    comprobar('Revisión: CURP sin especificar', i >= 0 and rev_no[i + 1] == 'Sin especificar',
              rev_no[i + 1] if i >= 0 else 'etiqueta ausente')
    captura(page, '04_revision_no')

    # --- Regreso al paso 3, Sí con 2 y de nuevo a la revisión
    for _ in range(5):
        anterior(page)
    comprobar('Paso anterior ×5 regresa al paso 3', paso_actual(page) == 3)
    respuesta(page, 'Sí')
    escribir(page, '¿Cuántos hijos tiene?', '2')
    for esperado in (4, 5, 6, 7, 8):
        llego = continuar(page)
        if llego != esperado:
            comprobar(f'Avanza al paso {esperado} con los datos conservados', False, f'paso {llego}')
            break
    comprobar('Llega a la revisión (paso 8) con Sí y 2', paso_actual(page) == 8)
    rev_si = revision(page)
    i = rev_si.index('¿Tiene hijos?') if '¿Tiene hijos?' in rev_si else -1
    j = rev_si.index('¿Cuántos hijos tiene?') if '¿Cuántos hijos tiene?' in rev_si else -1
    comprobar('Revisión con Sí: «¿Tiene hijos?» = Sí y «¿Cuántos hijos tiene?» = 2',
              i >= 0 and rev_si[i + 1] == 'Sí' and j >= 0 and rev_si[j + 1] == '2',
              ' | '.join(rev_si[max(i, 0):j + 2]) if i >= 0 else 'etiqueta ausente')
    captura(page, '05_revision_si')

    comprobar('El formulario no se envió (0 POST interceptados, 0 POST de registro)',
              not bloqueados and not any(r['metodo'] == 'POST' and r['ruta'] == '/ejecutivo/solicitudes' for r in mon.registros))
    page.unroute('**/ejecutivo/solicitudes')

    salida = {
        'escenario': 'T01 «¿Tiene hijos?» y CURP hasta la revisión, sin enviar',
        'fecha': time.strftime('%Y-%m-%d %H:%M:%S'),
        'aprobada': all(r['aprobada'] for r in resultados),
        'comprobaciones': resultados,
        'revision_con_no': rev_no,
        'revision_con_si': rev_si,
        'post_bloqueados': bloqueados,
        'peticiones': [{k: r[k] for k in ('metodo', 'ruta', 'codigo', 'servicio')} for r in mon.registros],
    }
    SALIDA.write_text(json.dumps(salida, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f"\n{sum(r['aprobada'] for r in resultados)}/{len(resultados)} comprobaciones aprobadas", flush=True)
