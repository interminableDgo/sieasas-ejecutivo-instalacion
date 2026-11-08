"""Genera calcomanía y tarjetas para jurado de SIEASAS (PNG y PDF).

Uso:
    python fuentes/build.py [URL] [TEXTO_URL]

URL        dirección a la que lleva el QR (por defecto, la página publicada en claude.ai)
TEXTO_URL  texto corto que se imprime bajo el QR (por ejemplo "sieasas.lovable.app");
           si se omite, no se imprime dirección.

Requiere: segno (pip install segno) y Microsoft Edge.
"""
import pathlib
import re
import subprocess
import sys

import segno

URL = sys.argv[1] if len(sys.argv) > 1 else "https://claude.ai/artifact/FC4hbXRdqYaJ2YFj396jfv"
URL_TEXT = sys.argv[2] if len(sys.argv) > 2 else ""

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "fuentes"
OUT = ROOT / "entregables"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

SYMBOL = (
    '<svg viewBox="0 0 250 120" aria-hidden="true">'
    '<polyline points="12,72 52,72 70,14 92,108 106,72 136,72" fill="none" stroke="#12A5E5" '
    'stroke-width="17" stroke-linecap="round" stroke-linejoin="round"/>'
    '<rect x="156" y="56" width="20" height="46" rx="10" fill="#FF8300"/>'
    '<rect x="190" y="34" width="20" height="68" rx="10" fill="#FF8300"/>'
    '<rect x="224" y="6" width="20" height="96" rx="10" fill="#FF8300"/>'
    "</svg>"
)


def qr_svg() -> str:
    qr = segno.make(URL, error="h")
    buf = __import__("io").BytesIO()
    qr.save(buf, kind="svg", scale=1, border=0, dark="#1B2A33", xmldecl=False, svgns=True)
    svg = buf.getvalue().decode()
    size = qr.symbol_size(scale=1, border=0)[0]
    svg = re.sub(r'width="\d+" height="\d+"', f'viewBox="0 0 {size} {size}" shape-rendering="crispEdges"', svg, count=1)
    qr.save(str(OUT / "qr.png"), scale=24, border=3, dark="#1B2A33")
    return svg


def sticker(qr: str) -> str:
    url_line = f'<div class="url">{URL_TEXT}</div>' if URL_TEXT else ""
    return f"""
<div class="sticker">
  <div style="display:flex;flex-direction:column;align-items:center">
    <div class="lockup">{SYMBOL}<span>sieasas</span></div>
    <div class="name">Sistema Integral Estatal de Atención<br>en Salud y Asistencia Social</div>
  </div>
  <div class="qr">{qr}</div>
  <div><div class="cta">Escanea y conoce el <b>software</b></div>{url_line}</div>
</div>"""


def card(qr: str) -> str:
    return f"""
<div class="card">
  {sticker(qr)}
  <div class="body">
    <span class="eyebrow">Para el jurado · PEF UDEM 2026</span>
    <h1>Del <span class="p">pulso</span> al <span class="d">dato</span>.</h1>
    <p>SIEASAS convierte cada solicitud de apoyo en salud y asistencia social de Nuevo León en información para decidir. Escanea el código para ver todas las especificaciones.</p>
    <ul>
      <li>Tablero de indicadores</li>
      <li>Del indicador al detalle</li>
      <li>Filtros y comparación</li>
      <li>Mapa por municipio</li>
      <li>Registro de solicitudes</li>
      <li>Exportación Excel y PDF</li>
    </ul>
    <div class="stack"><span><b>Flutter web</b> · FastAPI · <b>MySQL</b></span><span>Módulo Ejecutivo</span></div>
  </div>
  <div class="foot"><i></i><i></i></div>
</div>"""


def page(body: str, css: str) -> str:
    return (
        '<!doctype html><html lang="es"><head><meta charset="utf-8">'
        '<link rel="stylesheet" href="estilos.css">'
        f"<style>{css}</style></head><body>{body}</body></html>"
    )


def edge(args):
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--hide-scrollbars", *args],
                   check=True, capture_output=True, timeout=120)


def pdf(name: str, html: str):
    src = SRC / f"_{name}.html"
    src.write_text(html, encoding="utf-8")
    edge([f"--print-to-pdf={OUT / (name + '.pdf')}", src.as_uri()])


def png(name: str, html: str, w: int, h: int):
    src = SRC / f"_{name}.html"
    src.write_text(html, encoding="utf-8")
    edge([f"--screenshot={OUT / (name + '.png')}", f"--window-size={w},{h}", "--force-device-scale-factor=4",
          "--default-background-color=00000000", src.as_uri()])


def main():
    OUT.mkdir(exist_ok=True)
    qr = qr_svg()
    s, c = sticker(qr), card(qr)

    # Calcomanía individual (75 × 75 mm) en PDF y PNG transparente.
    pdf("calcomania", page(s, "@page{size:75mm 75mm;margin:0}"))
    png("calcomania", page(s, "html,body{background:transparent}"), 284, 284)

    # Hoja carta con 6 calcomanías para imprimir en papel adhesivo.
    grid = "".join(s for _ in range(6))
    pdf("calcomanias-hoja-carta", page(
        f'<div class="sheet">{grid}</div>',
        "@page{size:letter;margin:12mm}.sheet{display:grid;grid-template-columns:repeat(2,75mm);"
        "gap:10mm 14mm;justify-content:center;padding-top:6mm}"))

    # 5 tarjetas para jurado, una por página de 100 × 150 mm.
    pdf("tarjetas-jurado", page("".join(c for _ in range(5)),
        "@page{size:100mm 150mm;margin:0}.card{break-after:page}.card:last-child{break-after:auto}"))
    png("tarjeta-jurado", page(c, ""), 378, 567)

    # Las mismas 5 tarjetas en hojas carta (2 por hoja) con línea de corte punteada.
    sheets = []
    for i in range(0, 5, 2):
        pair = "".join(f'<div class="cut">{c}</div>' for _ in range(min(2, 5 - i)))
        sheets.append(f'<div class="sheet">{pair}</div>')
    pdf("tarjetas-jurado-hoja-carta", page("".join(sheets),
        "@page{size:letter;margin:10mm}.sheet{display:flex;gap:6mm;justify-content:center;padding-top:20mm;"
        "break-after:page}.sheet:last-child{break-after:auto}.cut{outline:0.3mm dashed #B9C2C7}"))

    for f in SRC.glob("_*.html"):
        f.unlink()
    print("Listo:", ", ".join(sorted(p.name for p in OUT.iterdir())))


if __name__ == "__main__":
    main()
