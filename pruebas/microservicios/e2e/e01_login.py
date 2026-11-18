"""E01: inicio de sesión (y 2FA si aplica) en el Chrome visible.
Si SGSC_E2E_CORREO y SGSC_E2E_CLAVE existen en el entorno, las escribe en los campos de Flutter;
nunca las imprime ni las guarda. Después espera a que el tablero cargue y registra las peticiones."""
import json
import os
import sys
import time

from playwright.sync_api import sync_playwright

from e2e_comun import Monitor, activar_semantica, conectar

SALIDA = sys.argv[1]
with sync_playwright() as pw:
    browser, page = conectar(pw)
    activar_semantica(page)
    mon = Monitor(page)
    page.bring_to_front()
    correo, clave = os.environ.pop('SGSC_E2E_CORREO', ''), os.environ.pop('SGSC_E2E_CLAVE', '')
    if correo and clave:
        page.locator('input[placeholder="correo@ejemplo.com"]').click()
        page.keyboard.type(correo, delay=20)
        page.locator('input').nth(1).click()
        page.keyboard.type(clave, delay=20)
        clave = None
        page.get_by_role('button', name='Iniciar sesión').click()
        print('Credenciales escritas en el formulario; esperando el tablero...', flush=True)
    else:
        print('ESPERANDO: inicia sesión en la ventana de Chrome (máx. 6 min)...', flush=True)
    limite = time.time() + 360
    ok = False
    while time.time() < limite:
        page.wait_for_timeout(1000)
        if any(r['ruta'] == '/ejecutivo/dashboard' and r['codigo'] == 200 for r in mon.registros):
            ok = True
            break
    page.wait_for_timeout(2500)
    tiene_token = mon.token() is not None
    rutas_auth = [r for r in mon.registros if r['ruta'].startswith('/auth/')]
    resultado = {'escenario': 'E01 Inicio de sesión y 2FA', 'aprobado': ok and tiene_token,
                 'login': [{k: r[k] for k in ('metodo', 'ruta', 'codigo', 'servicio', 'ms')} for r in rutas_auth],
                 'uso_2fa': any(r['ruta'] == '/auth/verify' for r in rutas_auth),
                 'peticiones_tras_login': [{k: r[k] for k in ('metodo', 'ruta', 'codigo', 'servicio', 'ms', 'consulta')}
                                           for r in mon.registros if not r['ruta'].startswith('/auth/')],
                 'token_en_memoria': tiene_token}
    json.dump(resultado, open(SALIDA, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(json.dumps(resultado, ensure_ascii=False, indent=1))
