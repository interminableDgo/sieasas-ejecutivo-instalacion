from html import escape
from pathlib import Path

APP_DIR = Path(__file__).resolve().parents[1]
LOGO_PATH = APP_DIR / 'assets/nl-logo.png'


def render_reset_email(link, logo_src='cid:siesas-logo'):
    template = (APP_DIR / 'templates/reset_password.html').read_text(encoding='utf-8')
    return template.replace('{{reset_url}}', escape(link, quote=True)).replace('{{logo_src}}', escape(logo_src, quote=True))


def reset_plain_text(link):
    return f'''SIESAS · Secretaría de Salud
Gobierno de Nuevo León

RECUPERA TU ACCESO

Recibimos una solicitud para restablecer la contraseña de tu cuenta de SIESAS.
Abre el siguiente enlace para elegir una nueva:

{link}

El enlace es válido durante 30 minutos y solo se puede utilizar una vez.

Si no solicitaste este cambio, ignora este correo. Tu contraseña permanecerá igual.

Mensaje automático. Nunca te pediremos tu contraseña por correo.
'''
