import ssl

import pytest

from app.services import auth_service
from app.services.auth_service import build_reset_message, enviar
from app.services.email_template import render_reset_email
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser


class _FakeSMTP:
    """Servidor SMTP simulado: registra las llamadas sin abrir conexiones."""

    instances = []

    def __init__(self, host, port, timeout=None, context=None):
        self.host, self.port, self.timeout, self.context = host, port, timeout, context
        self.calls = []
        _FakeSMTP.instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.calls.append('quit')
        return False

    def starttls(self, context=None):
        self.calls.append(('starttls', context))

    def login(self, user, password):
        self.calls.append(('login', user, password))

    def send_message(self, message):
        self.calls.append(('send', message['To']))


@pytest.fixture
def fake_smtp(monkeypatch):
    _FakeSMTP.instances = []
    monkeypatch.setattr(auth_service.smtplib, 'SMTP', _FakeSMTP)
    monkeypatch.setattr(auth_service.smtplib, 'SMTP_SSL', _FakeSMTP)
    monkeypatch.setenv('SMTP_HOST', 'smtp.example.com')
    return _FakeSMTP


def _mensaje():
    message = EmailMessage()
    message['To'] = 'recipient@example.com'
    message.set_content('hola')
    return message


def _verifica_certificado(context):
    assert isinstance(context, ssl.SSLContext)
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert context.check_hostname


def test_enviar_con_starttls_valida_certificado(fake_smtp, monkeypatch):
    monkeypatch.delenv('SMTP_SSL', raising=False)
    monkeypatch.delenv('SMTP_PORT', raising=False)
    monkeypatch.setenv('SMTP_USER', 'usuario')
    monkeypatch.setenv('SMTP_PASSWORD', 'secreto')
    enviar(_mensaje())
    smtp = fake_smtp.instances[0]
    assert (smtp.host, smtp.port, smtp.timeout, smtp.context) == ('smtp.example.com', 587, 15, None)
    assert smtp.calls[0][0] == 'starttls'
    _verifica_certificado(smtp.calls[0][1])
    assert smtp.calls[1:] == [('login', 'usuario', 'secreto'), ('send', 'recipient@example.com'), 'quit']


def test_enviar_con_ssl_directo_valida_certificado_sin_login(fake_smtp, monkeypatch):
    monkeypatch.setenv('SMTP_SSL', 'true')
    monkeypatch.setenv('SMTP_PORT', '2465')
    monkeypatch.delenv('SMTP_USER', raising=False)
    enviar(_mensaje())
    smtp = fake_smtp.instances[0]
    assert (smtp.port, smtp.timeout) == (2465, 15)
    _verifica_certificado(smtp.context)
    assert smtp.calls == [('send', 'recipient@example.com'), 'quit']


def test_email_embeds_logo_and_has_accessible_text(monkeypatch):
    monkeypatch.setenv('SMTP_HOST','smtp.example.com')
    monkeypatch.setenv('SMTP_FROM','no-reply@example.com')
    monkeypatch.setenv('RESET_URL','https://example.com/?lang=es&reset_token=old')
    message=build_reset_message('recipient@example.com','new-test-token')
    message=BytesParser(policy=policy.default).parsebytes(message.as_bytes(policy=policy.SMTP))
    plain=message.get_body(preferencelist=('plain',)).get_content()
    html=message.get_body(preferencelist=('html',)).get_content()
    assert 'reset_token=new-test-token' in plain
    assert 'reset_token=old' not in plain
    assert 'lang=es&amp;reset_token=new-test-token' in html
    logo=next(p for p in message.walk() if p.get_content_type()=='image/png')
    cid=str(logo['Content-ID'])
    assert cid.startswith('<') and cid.endswith('@example.com>')
    assert f'src="cid:{cid[1:-1]}"' in html
    related=next(p for p in message.walk() if p.get_content_type()=='multipart/related')
    assert related is message
    assert related.get_param('type')=='multipart/alternative'
    assert related.get_payload()[0].get_content_type()=='multipart/alternative'
    assert related.get_param('start')==related.get_payload()[0]['Content-ID']
    assert logo['X-Attachment-Id']==cid[1:-1]
    assert message['Date'] and message['Message-ID']
    assert logo.get_content_disposition()=='inline'
    assert logo.get_payload(decode=True).startswith(b'\x89PNG')
    assert '30 minutos' in html


def test_html_escapes_dynamic_url():
    html=render_reset_email('https://example.com/?q="<script>alert(1)</script>')
    assert '<script>' not in html
    assert '&lt;script&gt;' in html
