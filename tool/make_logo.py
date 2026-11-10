#!/usr/bin/env python3
"""Genera el emblema de Chasqui y todos los iconos de Android desde una sola
definición geométrica.

El emblema es punto, raya y punto: la R de la telegrafía, la misma marca que se
manda con la linterna. Los dos puntos son verdes y la raya ámbar, los dos colores
de la app. No hay arcos de wifi ni barras de cobertura, porque la app existe
justo cuando eso falta.

Uso:
    python tool/make_logo.py

Requiere Pillow. Escribe en android/app/src/main/res/, docs/ y assets/brand/.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
DOCS = ROOT / "docs"
BRAND = ROOT / "assets" / "brand"

MASTER = 1024
SUPERSAMPLE = 2

# Paleta: la misma semilla que ChasquiTheme.seed (0xFF0E9F6E), aclarada para que
# respire sobre fondo oscuro, más el ámbar de la raya.
INK = (8, 15, 20)
INK_LIGHT = (22, 35, 43)
GREEN = (22, 196, 137)
AMBER = (255, 176, 32)
WHITE = (255, 255, 255)

# Medidas del emblema, como fracción de su ancho total. Salen de la marca
# original: el punto mide 0.193 del ancho, la raya 0.378 y cada hueco 0.118.
GLYPH_SPAN = 0.625  # ancho del emblema respecto al lienzo maestro
ELEMENT = 0.1926  # alto de la raya y diámetro de los puntos
BAR_LEN = 0.3778  # largo de la raya


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
            fill=GREEN + (alpha,),
        )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.04))
    return Image.alpha_composite(img, glow)


def _glyph(size: int, span: float, *, monochrome: bool = False) -> Image.Image:
    """Punto, raya y punto centrados, dibujados con supersampling.

    `span` es el ancho total del emblema como fracción del lienzo. Se dibuja al
    doble y se reduce para que los bordes queden limpios hasta en 48 px.
    """
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    width = s * span
    height = width * ELEMENT
    bar = width * BAR_LEN
    dot = height

    left = s / 2 - width / 2
    top = s / 2 - height / 2
    right = left + width

    node_color = WHITE + (255,) if monochrome else GREEN + (255,)
    bar_color = WHITE + (255,) if monochrome else AMBER + (255,)

    draw.ellipse([left, top, left + dot, top + dot], fill=node_color)
    bar_left = left + dot + (width - 2 * dot - bar) / 2
    draw.rounded_rectangle(
        [bar_left, top, bar_left + bar, top + height],
        radius=height / 2,
        fill=bar_color,
    )
    draw.ellipse([right - dot, top, right, top + height], fill=node_color)

    return img.resize((size, size), Image.LANCZOS)


def _squircle(size: int, glyph_span: float) -> Image.Image:
    """Icono clásico: cuadrado con esquinas redondeadas y el emblema dentro."""
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
    return _glyph(size, GLYPH_SPAN * 0.99, monochrome=kind == "monochrome")


def _splash(size: int) -> Image.Image:
    return _glyph(size, 0.92)


LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
SPLASH = {"mdpi": 132, "hdpi": 198, "xhdpi": 264, "xxhdpi": 396, "xxxhdpi": 528}


def main() -> None:
    DOCS.mkdir(parents=True, exist_ok=True)
    BRAND.mkdir(parents=True, exist_ok=True)

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
    _glyph(512, 0.94).save(BRAND / "chasqui_logo.png")
    print("Logo generado: docs/, assets/brand/ y android/.../res/")


if __name__ == "__main__":
    main()
