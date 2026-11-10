#!/usr/bin/env python3
"""Erzeugt App-Icons, Startbilder und Bild-Assets aus den Vorlagen in design/.

Aufruf aus dem Projektordner:  python3 app/tool/brand_assets.py
Braucht Pillow und NumPy.
"""

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / 'design'
APP = ROOT / 'app'
RES = APP / 'android/app/src/main/res'
WHITE = (255, 255, 255, 255)


# --- Vorlagen zerlegen ------------------------------------------------------


def trim(arr, pad=4):
    ys, xs = np.nonzero(arr[:, :, 3] > 8)
    return Image.fromarray(arr).crop((
        max(xs.min() - pad, 0),
        max(ys.min() - pad, 0),
        min(xs.max() + pad + 1, arr.shape[1]),
        min(ys.max() + pad + 1, arr.shape[0]),
    ))


def split_sheet():
    """Maskottchen und Schriftzug aus dem Markenbild trennen."""
    sheet = np.array(Image.open(DESIGN / 'maskottchen.webp').convert('RGBA'))
    # Fast durchsichtige Reste der Freistellung wirken auf hellem Grund wie
    # graue Schlieren.
    sheet[sheet[:, :, 3] < 24] = 0
    # Der Schriftzug steht rechts unten, das Maskottchen reicht dort nicht hin.
    box = (slice(778, 1085), slice(876, None))
    word = np.zeros_like(sheet)
    word[box] = sheet[box]
    mascot = sheet.copy()
    mascot[box] = 0
    word = np.array(trim(word))
    # Nur „Bociva“ und Untertitel, ohne Linie und Herausgeber.
    rows = np.nonzero((word[:, :, 3] > 10).any(axis=1))[0]
    gaps = [y for y in range(rows[0], rows[-1]) if not (word[y, :, 3] > 10).any()]
    first_gap_end = next(y for y in gaps if y + 1 not in gaps)
    line_start = next(y for y in gaps if y > first_gap_end + 5)
    return trim(mascot), trim(word[:line_start])


def dark_variant(img):
    """Dunkelgrüne Schrift hell färben, das Blatt bleibt."""
    arr = np.array(img).astype(float)
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    t = np.clip((lum - 40) / 70, 0, 1)[..., None]
    light = (1 - t) * np.array([226, 243, 228]) + t * np.array([176, 214, 184])
    # Zeilen, in denen nur das Blatt steht (rechts oben), bleiben unverändert.
    opaque = arr[:, :, 3] > 10
    width = arr.shape[1]
    leaf_rows = np.array([
        row.any() and np.nonzero(row)[0].min() > width * 0.55 for row in opaque
    ])
    # Nur der zusammenhängende Block von oben, nicht etwa die Unterlänge des „g“.
    last_leaf = -1
    for y, (is_leaf, has) in enumerate(zip(leaf_rows, opaque.any(axis=1))):
        if has and not is_leaf:
            break
        if is_leaf:
            last_leaf = y
    # Das Blatt ist heller und kräftiger grün als die Schrift.
    dark = (lum < 115) & (arr[:, :, 1] < 118)
    dark[: last_leaf + 1] = False
    # Der Untertitel (nach der ersten Leerzeile unter der Schrift) ganz.
    has = opaque.any(axis=1)
    top = int(np.argmax(has))
    gap = top + int(np.argmin(has[top:]))
    dark[gap:] = opaque[gap:]
    dark = dark[..., None]
    arr[:, :, :3] = np.where(dark, light, arr[:, :, :3])
    return Image.fromarray(arr.astype(np.uint8))


def icon_artwork():
    """Das Motiv des App-Icons auf Weiß, ohne Kachel und Schatten."""
    src = Image.open(DESIGN / 'app-icon.webp').convert('RGBA')
    flat = Image.new('RGBA', src.size, WHITE)
    flat.alpha_composite(src)
    arr = np.array(flat.convert('RGB'))
    h, w = arr.shape[:2]
    # Von den Ecken aus alles fast Weiße füllen: Kachel, Schatten, Wolken.
    near = arr.min(axis=2) >= 226
    seen = np.zeros((h, w), bool)
    queue = deque([(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)])
    for p in queue:
        seen[p] = True
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and near[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    arr[seen] = 255
    # Lichtschein unter dem Motiv und Kachelränder.
    arr[1106:] = 255
    arr[:, :128] = 255
    arr[:, 1146:] = 255
    return Image.fromarray(arr).crop((128, 140, 1146, 1106))


def to_alpha(img):
    """Weiß wird durchsichtig (für Startbilder auf beliebigem Grund)."""
    a = np.array(img.convert('RGB')).astype(float)
    alpha = (255 - a).max(axis=2) / 255
    safe = np.maximum(alpha, 1e-6)[..., None]
    fg = np.where(alpha[..., None] > 0, (a - (1 - alpha[..., None]) * 255) / safe, 0)
    return Image.fromarray(np.dstack([np.clip(fg, 0, 255), alpha * 255]).astype(np.uint8))


# --- Icons zusammensetzen ---------------------------------------------------


def place(art, size, scale, background=WHITE, radius=0.0):
    """[art] mittig auf eine Fläche setzen, Breite = scale * size."""
    canvas = Image.new('RGBA', (size * 4, size * 4), (0, 0, 0, 0))
    if radius:
        ImageDraw.Draw(canvas).rounded_rectangle(
            (0, 0, size * 4 - 1, size * 4 - 1), radius=radius * size * 4, fill=background
        )
    elif background:
        canvas.paste(background, (0, 0, size * 4, size * 4))
    w = round(size * 4 * scale)
    h = round(w * art.height / art.width)
    scaled = art.convert('RGBA').resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(scaled, ((size * 4 - w) // 2, (size * 4 - h) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def save(img, path, rgb=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    (img.convert('RGB') if rgb else img).save(path, optimize=True)


def main():
    mascot, wordmark = split_sheet()
    art = icon_artwork()
    art_alpha = to_alpha(art)

    brand = APP / 'assets/brand'
    save(mascot.resize((600, round(600 * mascot.height / mascot.width)), Image.LANCZOS),
         brand / 'mascot.png')
    word = wordmark.resize((480, round(480 * wordmark.height / wordmark.width)), Image.LANCZOS)
    save(word, brand / 'wordmark.png')
    save(dark_variant(word), brand / 'wordmark_dark.png')

    # iOS: quadratisch, ohne Transparenz; die Ecken rundet das System.
    icons = APP / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for f in icons.glob('Icon-App-*.png'):
        base, factor = f.stem.removeprefix('Icon-App-').split('@')
        size = round(float(base.split('x')[0]) * int(factor.removesuffix('x')))
        save(place(art, size, 0.8), f, rgb=True)

    # Startbild iOS (weißer Grund im Storyboard).
    launch = APP / 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    for name, factor in (('LaunchImage.png', 1), ('LaunchImage@2x.png', 2), ('LaunchImage@3x.png', 3)):
        size = 140 * factor
        save(place(art_alpha, size, 1.0, background=None), launch / name)

    # Android: adaptives Icon (Vordergrund im 66-dp-Schutzbereich) und
    # klassisches Icon als Ersatz.
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, d in densities.items():
        save(place(art_alpha, round(108 * d), 0.56, background=None),
             RES / f'mipmap-{name}/ic_launcher_foreground.png')
        save(place(art, round(48 * d), 0.78, radius=0.22), RES / f'mipmap-{name}/ic_launcher.png')
        save(place(art_alpha, round(140 * d), 1.0, background=None),
             RES / f'drawable-{name}/launch_image.png')

    # Web: Favicon, PWA-Icons, Apple-Touch-Icon.
    web = APP / 'web'
    save(place(art, 64, 0.84, radius=0.22), web / 'favicon.png')
    for size in (192, 512):
        save(place(art, size, 0.78, radius=0.22), web / f'icons/Icon-{size}.png')
        save(place(art, size, 0.62), web / f'icons/Icon-maskable-{size}.png', rgb=True)
    save(place(art, 180, 0.8), web / 'icons/apple-touch-icon.png', rgb=True)
    print('fertig')


if __name__ == '__main__':
    main()
