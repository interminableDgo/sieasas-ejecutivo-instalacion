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


def test_no_responde_por_http_sin_cifrar(servidor):
    puerto, _, _ = servidor
    conexion = http.client.HTTPConnection('127.0.0.1', puerto, timeout=5)
    with pytest.raises((http.client.HTTPException, ConnectionError, OSError)):
        conexion.request('GET', '/')
        conexion.getresponse()
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
