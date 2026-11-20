import os
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr, formatdate, make_msgid, parseaddr
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from fastapi import HTTPException
from app.services.email_template import LOGO_PATH, render_reset_email, reset_plain_text


def mail_configured():
    return bool(os.getenv('SMTP_HOST') and os.getenv('SMTP_FROM') and os.getenv('RESET_URL'))


def build_reset_message(address, token):
    if not mail_configured():
        raise HTTPException(503, 'El servicio de recuperación por correo no está disponible.')
    message = EmailMessage()
    message['Subject'] = 'Recupera tu acceso a SIESAS'
    display, sender = parseaddr(os.environ['SMTP_FROM'])
    message['From'] = formataddr((display or os.getenv('SMTP_FROM_NAME', 'SIESAS · Gobierno de Nuevo León'), sender))
    message['To'] = address
    message['Date'] = formatdate(localtime=False)
    message['Message-ID'] = make_msgid(domain=sender.rsplit('@', 1)[-1])
    base = urlsplit(os.environ['RESET_URL'])
    params = [(key, value) for key, value in parse_qsl(base.query) if key != 'reset_token']
    params.append(('reset_token', token))
    link = urlunsplit(base._replace(query=urlencode(params)))
    message.make_related()
    body = EmailMessage()
    body.set_content(reset_plain_text(link))
    # A unique, fully qualified Content-ID lets mail clients resolve the image.
    logo_cid = make_msgid(domain=sender.rsplit('@', 1)[-1])
    body.add_alternative(render_reset_email(link, logo_src=f'cid:{logo_cid[1:-1]}'), subtype='html')
    body_cid = make_msgid(domain=sender.rsplit('@', 1)[-1])
    body['Content-ID'] = body_cid
    message.attach(body)
    message.add_related(LOGO_PATH.read_bytes(), maintype='image', subtype='png', cid=logo_cid, disposition='inline', filename='siesas-nuevo-leon.png')
    message.get_payload()[-1]['X-Attachment-Id'] = logo_cid[1:-1]
    message.set_param('type', 'multipart/alternative')
    message.set_param('start', body_cid)
    return message


def send_reset(address, token):
    enviar(build_reset_message(address, token))


def smtp_configurado():
    return bool(os.getenv('SMTP_HOST') and os.getenv('SMTP_FROM'))


def enviar(message):
    secure = os.getenv('SMTP_SSL', 'false').lower() == 'true'
    host = os.environ['SMTP_HOST']
    port = int(os.getenv('SMTP_PORT', '465' if secure else '587'))
    # Ambas ramas validan el certificado del servidor con el contexto TLS por defecto.
    context = ssl.create_default_context()
    if secure:
        with smtplib.SMTP_SSL(host, port, timeout=15, context=context) as smtp:
            _autenticar_y_enviar(smtp, message)
    else:
        with smtplib.SMTP(host, port, timeout=15) as smtp:
            smtp.starttls(context=context)
            _autenticar_y_enviar(smtp, message)


def _autenticar_y_enviar(smtp, message):
    if os.getenv('SMTP_USER'):
        smtp.login(os.environ['SMTP_USER'], os.environ.get('SMTP_PASSWORD', ''))
    smtp.send_message(message)

