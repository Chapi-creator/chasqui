#!/usr/bin/env python3
"""Genera el logo de SinRed y todos los iconos de Android desde una sola
definición geométrica.

El logo es una red: un rombo de cuatro nodos conectados al centro. No hay
arcos de wifi ni barras de cobertura, porque la app existe justo cuando eso
falta; lo que se ve es la malla que queda cuando no hay torres.

Uso:
    python tool/make_logo.py

Requiere Pillow. Escribe en android/app/src/main/res/ y en docs/.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
DOCS = ROOT / "docs"

MASTER = 1024
SUPERSAMPLE = 2

# Paleta: la misma semilla que SinRedTheme.seed (0xFF0E9F6E), aclarada para que
# respire sobre fondo oscuro, más un ámbar de emergencia para el nodo central.
INK = (8, 15, 20)
INK_LIGHT = (22, 35, 43)
GREEN = (23, 196, 138)
GREEN_BRIGHT = (43, 227, 155)
AMBER = (255, 176, 32)
WHITE = (255, 255, 255)

GLYPH_SPAN = 0.625  # diámetro del rombo respecto al lienzo maestro
LINE_WIDTH = 52
NODE_RADIUS = 84
HUB_RADIUS = 102


def _background(size: int) -> Image.Image:
    """Fondo cuadrangular: degradado diagonal + halo verde detrás del centro."""
    img = Image.new("RGBA", (size, size), INK + (255,))
    draw = ImageDraw.Draw(img)
    steps = size * 2
    for i in range(steps):
        t = i / (steps - 1)
        color = tuple(
            int(INK[j] + (INK_LIGHT[j] - INK[j]) * (1 - t)) for j in range(3)
        )
        draw.line([(0, i), (i, 0)], fill=color + (255,), width=max(2, size // 400))

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    radius = size * 0.52
    steps = 60
    for i in range(steps, 0, -1):
        r = radius * i / steps
        alpha = int(26 * (1 - i / steps) ** 1.6)
        gdraw.ellipse(
            [size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r],
            fill=(emerald := GREEN)[0:3] + (alpha,),
        )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.04))
    return Image.alpha_composite(img, glow)


def _diamond(center: float, half: float) -> list[tuple[float, float]]:
    return [
        (center, center - half),
        (center + half, center),
        (center, center + half),
        (center - half, center),
    ]


def _glyph(
    size: int,
    span: float,
    *,
    monochrome: bool = False,
    hub: bool = True,
) -> Image.Image:
    """El dibujo en sí: rombo de nodos con radios hacia el centro.

    `span` es el diámetro del rombo como fracción del lienzo. Se dibuja con
    supersampling y se reduce para que los bordes queden limpios en 48 px.
    """
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    center = s / 2
    half = s * span / 2
    line_color = WHITE + (255,) if monochrome else GREEN + (235,)
    node_color = WHITE + (255,) if monochrome else GREEN_BRIGHT + (255,)
    width = max(2, int(LINE_WIDTH / MASTER * s))

    points = _diamond(center, half)
    draw.line(points + [points[0]], fill=line_color, width=width, joint="curve")
    for point in points:
        draw.line([(center, center), point], fill=line_color, width=width)
        # Un disco del color de la línea tapa la junta del rombo.
        draw.ellipse(
            [point[0] - width / 2, point[1] - width / 2,
             point[0] + width / 2, point[1] + width / 2],
            fill=line_color,
        )

    radius = NODE_RADIUS / MASTER * s
    for point in points:
        draw.ellipse(
            [point[0] - radius, point[1] - radius,
             point[0] + radius, point[1] + radius],
            fill=node_color,
        )

    if hub:
        hub_radius = HUB_RADIUS / MASTER * s
        if monochrome:
            # En el icono temático el centro queda hueco: así el dibujo no se
            # convierte en una mancha cuando el sistema lo tiñe de un color.
            hole = hub_radius * 1.5
            draw.ellipse(
                [center - hole, center - hole, center + hole, center + hole],
                fill=(0, 0, 0, 0),
            )
        else:
            draw.ellipse(
                [center - hub_radius, center - hub_radius,
                 center + hub_radius, center + hub_radius],
                fill=AMBER + (255,),
            )

    return img.resize((size, size), Image.LANCZOS)


def _squircle(size: int, glyph_span: float) -> Image.Image:
    """Icono clásico: cuadrado con esquinas redondeadas y el dibujo dentro."""
    base = _background(size)
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    radius = int(size * 0.225)
    mdraw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    base.putalpha(mask)
    return Image.alpha_composite(base, _glyph(size, glyph_span))


def _circle(size: int, glyph_span: float) -> Image.Image:
    base = _background(size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    base.putalpha(mask)
    return Image.alpha_composite(base, _glyph(size, glyph_span))


def _adaptive_layer(size: int, kind: str) -> Image.Image:
    """Capa de icono adaptativo (108 dp de lienzo, contenido dentro de 72 dp)."""
    if kind == "background":
        return _background(size)
    if kind == "foreground":
        return _glyph(size, GLYPH_SPAN * 0.99)
    return _glyph(size, GLYPH_SPAN * 0.99, monochrome=True, hub=True)


def _splash(size: int) -> Image.Image:
    return _glyph(size, 0.92, hub=True)


LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
SPLASH = {"mdpi": 132, "hdpi": 198, "xhdpi": 264, "xxhdpi": 396, "xxxhdpi": 528}


def main() -> None:
    DOCS.mkdir(parents=True, exist_ok=True)

    for density, size in LEGACY.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        _squircle(size, GLYPH_SPAN).save(folder / "ic_launcher.png")
        _circle(size, GLYPH_SPAN * 0.94).save(folder / "ic_launcher_round.png")

    for density, size in ADAPTIVE.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        for kind in ("background", "foreground", "monochrome"):
            _adaptive_layer(size, kind).save(folder / f"ic_launcher_{kind}.png")

    for density, size in SPLASH.items():
        folder = RES / f"drawable-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        _splash(size).save(folder / "splash_logo.png")

    # Recursos compartidos: README y pantalla "Acerca de".
    # 512 basta para el README y no engorda el repo con un PNG de 1024.
    _squircle(512, GLYPH_SPAN).save(DOCS / "logo.png")
    (ROOT / "assets" / "brand").mkdir(parents=True, exist_ok=True)
    _glyph(512, 0.94).save(ROOT / "assets" / "brand" / "sinred_logo.png")
    print("Logo generado: docs/, assets/brand/ y android/.../res/")


if __name__ == "__main__":
    main()
