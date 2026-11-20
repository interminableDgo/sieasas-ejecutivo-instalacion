import gzip
import http.client
import ssl
import threading

import pytest

import serve_web


@pytest.fixture
def servidor(tmp_path):
    root = tmp_path / 'web'
    root.mkdir()
    (root / 'index.html').write_text('<h1>SIESAS</h1>', encoding='utf-8')
    cert, key = tmp_path / 'web.crt', tmp_path / 'web.key'
    httpd = serve_web.crear_servidor(root, port=0, cert=cert, key=key)
    hilo = threading.Thread(target=httpd.serve_forever, daemon=True)
    hilo.start()
    try:
        yield httpd.server_address[1], cert, key
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_sirve_por_https_con_certificado_valido_para_127(servidor):
    puerto, cert, _ = servidor
    contexto = ssl.create_default_context(cafile=str(cert))  # valida certificado y nombre
    conexion = http.client.HTTPSConnection('127.0.0.1', puerto, context=contexto, timeout=5)
    conexion.request('GET', '/?reset_token=secreto')
    respuesta = conexion.getresponse()
    assert respuesta.status == 200
    assert b'SIESAS' in respuesta.read()
    assert respuesta.getheader('Strict-Transport-Security') == 'max-age=31536000'
    assert respuesta.getheader('Referrer-Policy') == 'no-referrer'
    conexion.close()


def _https(puerto, cert):
    contexto = ssl.create_default_context(cafile=str(cert))
    return http.client.HTTPSConnection('127.0.0.1', puerto, context=contexto, timeout=5)


def test_comprime_con_gzip_si_el_navegador_lo_acepta(servidor):
    puerto, cert, _ = servidor
    conexion = _https(puerto, cert)
    conexion.request('GET', '/', headers={'Accept-Encoding': 'gzip, br'})
    respuesta = conexion.getresponse()
    cuerpo = respuesta.read()
    assert respuesta.status == 200
    assert respuesta.getheader('Content-Encoding') == 'gzip'
    assert respuesta.getheader('Vary') == 'Accept-Encoding'
    assert respuesta.getheader('Content-Type') == 'text/html'
    assert respuesta.getheader('Cache-Control') == 'no-store'
    assert gzip.decompress(cuerpo) == '<h1>SIESAS</h1>'.encode()
    conexion.close()


def test_sin_gzip_si_no_lo_acepta_y_archivos_no_comprimibles(servidor, tmp_path):
    puerto, cert, _ = servidor
    (tmp_path / 'web' / 'logo.png').write_bytes(b'\x89PNG')
    conexion = _https(puerto, cert)
    conexion.request('GET', '/index.html')
    respuesta = conexion.getresponse()
    assert respuesta.getheader('Content-Encoding') is None and b'SIESAS' in respuesta.read()
    conexion.request('GET', '/logo.png', headers={'Accept-Encoding': 'gzip'})
    respuesta = conexion.getresponse()
    assert respuesta.getheader('Content-Encoding') is None and respuesta.read() == b'\x89PNG'
    conexion.close()


def test_no_responde_por_http_sin_cifrar(servidor):
    puerto, _, _ = servidor
    conexion = http.client.HTTPConnection('127.0.0.1', puerto, timeout=5)
    with pytest.raises((http.client.HTTPException, ConnectionError, OSError)):
        conexion.request('GET', '/')
        conexion.getresponse()
    conexion.close()


@pytest.fixture
def api_falsa(monkeypatch):
    """API mínima en otro puerto que registra lo que recibe; serve_web le reenvía las rutas de la API."""
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    recibido = {}

    class Api(BaseHTTPRequestHandler):
        def _responder(self):
            largo = int(self.headers.get('Content-Length') or 0)
            recibido.update(metodo=self.command, ruta=self.path, cuerpo=self.rfile.read(largo),
                            autorizacion=self.headers.get('Authorization'), tipo=self.headers.get('Content-Type'))
            estado = 401 if self.path.startswith('/auth/me') else 201
            datos = b'{"ok":true}'
            self.send_response(estado)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Disposition', 'attachment; filename="reporte.xlsx"')
            self.send_header('X-SGSC-Service', 'prueba')
            self.send_header('Content-Length', str(len(datos)))
            self.end_headers()
            self.wfile.write(datos)

        do_GET = do_POST = _responder

        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(('127.0.0.1', 0), Api)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    monkeypatch.setattr(serve_web.Handler, 'api', 'http://127.0.0.1:%d' % httpd.server_address[1])
    try:
        yield recibido
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_reenvia_a_la_api_con_metodo_cuerpo_y_autorizacion(servidor, api_falsa):
    puerto, cert, _ = servidor
    conexion = _https(puerto, cert)
    conexion.request('POST', '/ejecutivo/solicitudes?x=1', body=b'{"a":1}',
                     headers={'Authorization': 'Bearer abc', 'Content-Type': 'application/json'})
    respuesta = conexion.getresponse()
    assert respuesta.status == 201 and respuesta.read() == b'{"ok":true}'
    assert respuesta.getheader('Content-Disposition') == 'attachment; filename="reporte.xlsx"'
    assert respuesta.getheader('X-SGSC-Service') == 'prueba'
    assert respuesta.getheader('Cache-Control') == 'no-store'
    assert api_falsa == {'metodo': 'POST', 'ruta': '/ejecutivo/solicitudes?x=1', 'cuerpo': b'{"a":1}',
                         'autorizacion': 'Bearer abc', 'tipo': 'application/json'}
    conexion.close()


def test_devuelve_los_errores_de_la_api_tal_cual(servidor, api_falsa):
    puerto, cert, _ = servidor
    conexion = _https(puerto, cert)
    conexion.request('GET', '/auth/me')
    respuesta = conexion.getresponse()
    assert respuesta.status == 401 and respuesta.read() == b'{"ok":true}'
    conexion.close()


def test_responde_502_si_la_api_no_esta_encendida(servidor, monkeypatch):
    import socket
    libre = socket.socket()
    libre.bind(('127.0.0.1', 0))
    puerto_cerrado = libre.getsockname()[1]
    libre.close()
    monkeypatch.setattr(serve_web.Handler, 'api', 'http://127.0.0.1:%d' % puerto_cerrado)
    puerto, cert, _ = servidor
    conexion = _https(puerto, cert)
    conexion.request('GET', '/health/db')
    respuesta = conexion.getresponse()
    assert respuesta.status == 502 and b'API local no responde' in respuesta.read()
    conexion.close()


def test_solo_las_rutas_de_la_api_aceptan_post(servidor):
    puerto, cert, _ = servidor
    conexion = _https(puerto, cert)
    conexion.request('POST', '/index.html', body=b'x')
    respuesta = conexion.getresponse()
    respuesta.read()
    assert respuesta.status == 405
    conexion.close()


def test_certificado_se_reutiliza_y_se_renueva_al_vencer(tmp_path):
    cert, key = tmp_path / 'c.crt', tmp_path / 'c.key'
    assert not serve_web.certificado_vigente(cert, key)
    serve_web.contexto_tls(cert, key)
    primero = cert.read_bytes()
    serve_web.contexto_tls(cert, key)
    assert cert.read_bytes() == primero  # vigente: no se regenera
    serve_web.generar_certificado(cert, key, dias=1)
    assert not serve_web.certificado_vigente(cert, key)  # vence en menos de 7 días
    serve_web.contexto_tls(cert, key)
    assert serve_web.certificado_vigente(cert, key)
