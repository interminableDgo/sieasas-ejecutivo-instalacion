"""Loopback-only HTTPS preview server; recovery tokens are never written to access logs.

La primera vez genera un certificado autofirmado para 127.0.0.1 y localhost
(serve_web.local.crt / serve_web.local.key, excluidos de Git por backend/*.local.*).
Se renueva solo cuando falta o está por vencer.

Como el gateway en producción, reenvía /auth, /ejecutivo y /health a la API local
(SERVE_WEB_API, por omisión http://127.0.0.1:8000). Así la app y la API comparten la misma
dirección HTTPS y el navegador no bloquea las llamadas: con un certificado autofirmado, una
página HTTPS no puede llamar a una API en otra dirección por HTTP.
"""
import datetime
import gzip
import ipaddress
import os
import ssl
import urllib.error
import urllib.request
from functools import lru_cache, partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HOST = '127.0.0.1'
PORT = 5173
BACKEND = Path(__file__).resolve().parent
CERT = BACKEND / 'serve_web.local.crt'
KEY = BACKEND / 'serve_web.local.key'
# Igual que gateway/nginx.conf: texto, JavaScript, WebAssembly y fuentes se envían con gzip.
COMPRIMIBLES = {'.html', '.css', '.js', '.mjs', '.json', '.wasm', '.svg', '.ttf', '.otf', '.txt'}
API = os.getenv('SERVE_WEB_API', 'http://127.0.0.1:8000').rstrip('/')
RUTAS_API = ('/auth/', '/ejecutivo/', '/health')
# Encabezados que la API necesita y los que la app necesita de vuelta (incluido el nombre de los reportes).
ENCABEZADOS_PETICION = ('Authorization', 'Content-Type', 'Accept', 'Accept-Language')
ENCABEZADOS_RESPUESTA = ('Content-Type', 'Content-Disposition', 'X-SGSC-Service')


class _SinRedireccion(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


_cliente_api = urllib.request.build_opener(_SinRedireccion)


@lru_cache(maxsize=64)
def _gzip(ruta, modificado):
    # `modificado` forma parte de la llave: si el archivo cambia, se vuelve a comprimir.
    return gzip.compress(Path(ruta).read_bytes(), compresslevel=6)


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm'}
    api = API

    def _es_api(self):
        return urlsplit(self.path).path.startswith(RUTAS_API)

    def _reenviar(self):
        largo = int(self.headers.get('Content-Length') or 0)
        cuerpo = self.rfile.read(largo) if largo else None
        peticion = urllib.request.Request(self.api + self.path, data=cuerpo, method=self.command,
                                          headers={k: self.headers[k] for k in ENCABEZADOS_PETICION if self.headers.get(k)})
        try:
            respuesta = _cliente_api.open(peticion, timeout=120)
        except urllib.error.HTTPError as error:  # 401, 404, 422, 503…: se devuelven tal cual
            respuesta = error
        except OSError:
            datos = b'{"detail":"La API local no responde. Inicia la API en el puerto 8000."}'
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(datos)))
            self.end_headers()
            self.wfile.write(datos)
            return
        with respuesta:
            datos = respuesta.read()
            self.send_response(respuesta.status)
            for nombre in ENCABEZADOS_RESPUESTA:
                if respuesta.headers.get(nombre):
                    self.send_header(nombre, respuesta.headers[nombre])
            self.send_header('Content-Length', str(len(datos)))
            self.end_headers()
            self.wfile.write(datos)

    def do_POST(self):
        if self._es_api(): return self._reenviar()
        self.send_error(405)

    def do_PUT(self):
        if self._es_api(): return self._reenviar()
        self.send_error(405)

    def do_PATCH(self):
        if self._es_api(): return self._reenviar()
        self.send_error(405)

    def do_DELETE(self):
        if self._es_api(): return self._reenviar()
        self.send_error(405)

    def do_GET(self):
        if self._es_api():
            return self._reenviar()
        ruta = Path(self.translate_path(self.path))
        if ruta.is_dir() and urlsplit(self.path).path.endswith('/'):
            ruta = ruta / 'index.html'
        acepta_gzip = 'gzip' in self.headers.get('Accept-Encoding', '')
        if not (acepta_gzip and ruta.suffix in COMPRIMIBLES and ruta.is_file()):
            return super().do_GET()
        datos = _gzip(str(ruta), ruta.stat().st_mtime_ns)
        self.send_response(200)
        self.send_header('Content-Type', self.guess_type(str(ruta)))
        self.send_header('Content-Encoding', 'gzip')
        self.send_header('Vary', 'Accept-Encoding')
        self.send_header('Content-Length', str(len(datos)))
        self.end_headers()
        self.wfile.write(datos)

    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        self.send_header('Referrer-Policy','no-referrer')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Strict-Transport-Security','max-age=31536000')
        super().end_headers()

    def log_request(self, code='-', size='-'):
        self.log_message('%s %s %s',self.command,urlsplit(self.path).path,code)


def certificado_vigente(cert=CERT, key=KEY, margen=datetime.timedelta(days=7)):
    from cryptography import x509
    if not (cert.exists() and key.exists()):
        return False
    vence = x509.load_pem_x509_certificate(cert.read_bytes()).not_valid_after_utc
    return vence - margen > datetime.datetime.now(datetime.timezone.utc)


def generar_certificado(cert=CERT, key=KEY, dias=365):
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    llave = ec.generate_private_key(ec.SECP256R1())
    nombre = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'SIESAS local')])
    ahora = datetime.datetime.now(datetime.timezone.utc)
    certificado = (
        x509.CertificateBuilder()
        .subject_name(nombre)
        .issuer_name(nombre)
        .public_key(llave.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(ahora - datetime.timedelta(minutes=5))
        .not_valid_after(ahora + datetime.timedelta(days=dias))
        .add_extension(x509.SubjectAlternativeName([
            x509.IPAddress(ipaddress.ip_address(HOST)), x509.DNSName('localhost')]), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(llave, hashes.SHA256())
    )
    key.write_bytes(llave.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    cert.write_bytes(certificado.public_bytes(serialization.Encoding.PEM))


def contexto_tls(cert=CERT, key=KEY):
    if not certificado_vigente(cert, key):
        generar_certificado(cert, key)
    contexto = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    contexto.minimum_version = ssl.TLSVersion.TLSv1_2
    contexto.load_cert_chain(cert, key)
    return contexto


def crear_servidor(root, host=HOST, port=PORT, cert=CERT, key=KEY):
    servidor = ThreadingHTTPServer((host, port), partial(Handler, directory=str(root)))
    servidor.socket = contexto_tls(cert, key).wrap_socket(servidor.socket, server_side=True)
    return servidor


if __name__=='__main__':
    root=BACKEND.parent/'sgsc_ejecutiva/build/web'
    if not (root/'index.html').exists():
        raise SystemExit('Primero compila Flutter web.')
    crear_servidor(root).serve_forever()
