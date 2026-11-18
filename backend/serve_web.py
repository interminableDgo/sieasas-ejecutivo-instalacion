"""Loopback-only HTTPS preview server; recovery tokens are never written to access logs.

La primera vez genera un certificado autofirmado para 127.0.0.1 y localhost
(serve_web.local.crt / serve_web.local.key, excluidos de Git por backend/*.local.*).
Se renueva solo cuando falta o está por vencer.
"""
import datetime
import ipaddress
import ssl
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HOST = '127.0.0.1'
PORT = 5173
BACKEND = Path(__file__).resolve().parent
CERT = BACKEND / 'serve_web.local.crt'
KEY = BACKEND / 'serve_web.local.key'


class Handler(SimpleHTTPRequestHandler):
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
