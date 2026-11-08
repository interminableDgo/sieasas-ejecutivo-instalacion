"""Ronda 2: símbolos de una sola idea, espacio negativo, logotipo en minúsculas."""
import math
import os
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT, FONT = sys.argv[1], sys.argv[2]
OUT = os.path.join(ROOT, "logo", "ronda-2")
WEIGHT = int(os.environ.get("WGHT", "700"))


def P(d, eo=False):
    rule = ' fill-rule="evenodd"' if eo else ""
    return f'<path d="{d}"{rule}/>'


def corner_rect(x, y, w, h, tl, tr, br, bl):
    return (f"M{x+tl},{y}H{x+w-tr}A{tr},{tr} 0 0 1 {x+w},{y+tr}V{y+h-br}"
            f"A{br},{br} 0 0 1 {x+w-br},{y+h}H{x+bl}A{bl},{bl} 0 0 1 {x},{y+h-bl}"
            f"V{y+tl}A{tl},{tl} 0 0 1 {x+tl},{y}Z")


def circle(cx, cy, r):
    return f"M{cx-r},{cy}A{r},{r} 0 1 0 {cx+r},{cy}A{r},{r} 0 1 0 {cx-r},{cy}Z"


def pt(c, r, deg):
    a = math.radians(deg)
    return c[0] + r * math.cos(a), c[1] + r * math.sin(a)


def arc_stroke(c, R, t, a0, a1):
    """Arco con remates redondos, convertido a relleno."""
    ro, ri, h = R + t / 2, R - t / 2, t / 2
    large = 1 if abs(a1 - a0) > 180 else 0
    f = lambda p: f"{p[0]:.3f},{p[1]:.3f}"
    o0, o1, i0, i1 = pt(c, ro, a0), pt(c, ro, a1), pt(c, ri, a0), pt(c, ri, a1)
    return (f"M{f(o0)}A{ro},{ro} 0 {large} 1 {f(o1)}A{h},{h} 0 0 1 {f(i1)}"
            f"A{ri},{ri} 0 {large} 0 {f(i0)}A{h},{h} 0 0 1 {f(o0)}Z")


def plus(cx, cy, s, b):
    a, b = s / 2, b / 2
    pts = [(-b, -a), (b, -a), (b, -b), (a, -b), (a, b), (b, b),
           (b, a), (-b, a), (-b, b), (-a, b), (-a, -b), (-b, -b)]
    return "M" + "L".join(f"{cx+x:g},{cy+y:g}" for x, y in pts) + "Z"


# ---------------- símbolos, lienzo 120×120 ----------------
def tiles(radii, g=16):
    s = (120 - g) / 2
    o = s + g
    pos = [(0, 0), (o, 0), (o, o), (0, o)]
    return [P(corner_rect(x, y, s, s, *r)) for (x, y), r in zip(pos, radii)]


def sym_tablero():
    # Cuatro tarjetas de tablero; la cruz de salud vive en el espacio entre ellas.
    R, r = 22, 6
    return tiles([(R, r, r, r), (r, R, r, r), (r, r, R, r), (r, r, r, R)])


def sym_hoja():
    # La misma retícula, pero dos esquinas se vuelven curva: una hoja (vida, bienestar)
    # partida por la cruz.
    R, r = 52, 6
    return tiles([(R, r, r, r), (r, r, r, r), (r, r, R, r), (r, r, r, r)])


def sym_pastel():
    # Gráfica de pastel partida por la cruz; un cuarto se separa: el detalle de un indicador.
    cx, cy, R, h = 54, 66, 50, 6
    k = (R * R - h * h) ** 0.5
    def quad(sx, sy, dx=0, dy=0):
        x0, y0 = cx + sx * h + dx, cy + sy * h + dy
        p1 = (cx + sx * h + dx, cy + sy * k + dy)
        p2 = (cx + sx * k + dx, cy + sy * h + dy)
        sweep = 1 if sx * sy < 0 else 0
        return P(f"M{x0:.3f},{y0:.3f}L{p1[0]:.3f},{p1[1]:.3f}"
                 f"A{R},{R} 0 0 {sweep} {p2[0]:.3f},{p2[1]:.3f}Z")
    return [quad(-1, -1), quad(1, -1, 10, -10), quad(1, 1), quad(-1, 1)]


def sym_ciudadano():
    # Tres tarjetas de datos y una persona: el ciudadano es parte del tablero.
    R, r = 22, 6
    t = tiles([(R, r, r, r), (r, R, r, r), (r, r, R, r), (r, r, r, R)])
    return [t[0], P(circle(94, 26, 26)), t[2], t[3]]


SYMBOLS = [
    ("a-tablero", "Tablero", sym_tablero, ""),
    ("b-pastel", "Pastel", sym_pastel, ""),
    ("c-hoja", "Hoja", sym_hoja, ""),
    ("d-ciudadano", "Ciudadano", sym_ciudadano, ""),
]


# ---------------- logotipo ----------------
def load_font():
    f = instancer.instantiateVariableFont(TTFont(FONT), {"wght": WEIGHT})
    return f, f.getGlyphSet(), f.getBestCmap()


def word(text, gs, cmap, tracking=10, plus_i=False):
    x, parts, xh = 0, [], 500
    for ch in text:
        name = cmap[0x131] if (plus_i and ch == "i") else cmap[ord(ch)]
        pen = SVGPathPen(gs)
        gs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, xh)))
        parts.append(P(pen.getCommands()))
        if plus_i and ch == "i":
            bp = BoundsPen(gs)
            gs[name].draw(bp)
            x0, _, x1, _ = bp.bounds
            bi = BoundsPen(gs)
            gs[cmap[ord("i")]].draw(bi)
            stem = x1 - x0
            dot_top = bi.bounds[3]
            size = stem * 1.45
            cy = xh - (dot_top - size / 2) - 8
            cx = x + (x0 + x1) / 2
            parts.append(P(plus(cx, cy, size, stem * 0.5)))
        x += gs[name].width + tracking
    return parts, x - tracking, xh


def svg(w, h, body, vy=0):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {vy:g} {w:g} {h:g}">'
            f'<g fill="#000000">{"".join(body)}</g></svg>\n')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)


def main():
    _, gs, cmap = load_font()
    words, ww, xh = word("siesas", gs, cmap)
    for slug, _, fn, _ in SYMBOLS:
        d = os.path.join(OUT, slug)
        body = fn()
        write(os.path.join(d, "simbolo.svg"), svg(120, 120, body))
        # Horizontal: altura x del texto = 46 % del símbolo, centrada.
        s = 55 / xh
        gap = 30
        t = f'<g transform="translate({120+gap},{(120-55)/2:g}) scale({s:.6f})">{"".join(words)}</g>'
        write(os.path.join(d, "horizontal.svg"), svg(120 + gap + ww * s, 120, body + [t]))
        # Vertical
        s2 = 30 / xh
        tw = ww * s2
        vw = max(120, tw)
        t2 = f'<g transform="translate({(vw-tw)/2:g},{120+28}) scale({s2:.6f})">{"".join(words)}</g>'
        sym = f'<g transform="translate({(vw-120)/2:g},0)">{"".join(body)}</g>'
        write(os.path.join(d, "vertical.svg"), svg(vw, 120 + 28 + 33, [sym, t2]))

    print("ok")


if __name__ == "__main__":
    main()
