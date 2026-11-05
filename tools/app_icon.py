"""App icon from the author's Li knight (tools/assets/li_knight.svg).

The SVG is made of circles, squares (each with an affine transform) and one
stroked polyline (the head). Blue shapes are the knight, orange ones are
holes. The knight is drawn white on the app's dark background, rendered 4x and
scaled down, into the Android launcher icons and the web icons.

Run: python3 tools/app_icon.py
"""

import math
import pathlib
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "tools/assets/li_knight.svg"
BLUE, ORANGE = "#8ab4d8", "#e0a06a"
BG = (18, 22, 20, 255)
FG = (242, 242, 242, 255)
SS = 4  # supersampling


def matrix(el):
    nums = re.findall(r"[-\d.e]+", el.get("transform", "matrix(1,0,0,1,0,0)"))
    return tuple(map(float, nums))


def apply(m, x, y):
    a, b, c, d, e, f = m
    return a * x + c * y + e, b * x + d * y + f


def shapes():
    """(kind, cut, points or (points, width)) in SVG coordinates."""
    out = []
    for el in ET.parse(SRC).getroot():
        tag = el.tag.split("}")[-1]
        m = matrix(el)
        if tag == "circle":
            r = float(el.get("r"))
            pts = [apply(m, r * math.cos(t * math.pi / 48), r * math.sin(t * math.pi / 48)) for t in range(96)]
            out.append(("poly", el.get("fill", "").lower() == ORANGE, pts))
        elif tag == "rect":
            x, y = float(el.get("x")), float(el.get("y"))
            w, h = float(el.get("width")), float(el.get("height"))
            pts = [apply(m, px, py) for px, py in ((x, y), (x + w, y), (x + w, y + h), (x, y + h))]
            out.append(("poly", el.get("fill", "").lower() == ORANGE, pts))
        elif tag == "path":
            nums = list(map(float, re.findall(r"[-\d.e]+", el.get("d"))))
            pts = [apply(m, nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)]
            width = float(el.get("stroke-width", "1"))
            out.append(("line", el.get("stroke", "").lower() == ORANGE, (pts, width)))
    return out


def bounds(items):
    xs, ys = [], []
    for kind, cut, data in items:
        if cut:
            continue
        pts = data if kind == "poly" else data[0]
        pad = 0 if kind == "poly" else data[1] / 2
        xs += [p[0] - pad for p in pts] + [p[0] + pad for p in pts]
        ys += [p[1] - pad for p in pts] + [p[1] + pad for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def render(size, fill=0.62, round_corners=False):
    items = shapes()
    x0, y0, x1, y1 = bounds(items)
    big = size * SS
    s = big * fill / max(x1 - x0, y1 - y0)
    ox = (big - (x1 - x0) * s) / 2 - x0 * s
    oy = (big - (y1 - y0) * s) / 2 - y0 * s
    tr = lambda p: (p[0] * s + ox, p[1] * s + oy)  # noqa: E731
    knight = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(knight)
    for kind, cut, data in items:
        value = 0 if cut else 255
        if kind == "poly":
            d.polygon([tr(p) for p in data], fill=value)
        else:
            # круглое перо, прокатанное по линии: ровные края и скругления
            pts, width = data
            r = width * s / 2
            q = [tr(p) for p in pts]
            for (ax, ay), (bx, by) in zip(q, q[1:] + q[-1:]):
                n = max(1, int(math.hypot(bx - ax, by - ay) / (r / 4)))
                for k in range(n):
                    cx, cy = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
                    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=value)
    img = Image.new("RGBA", (big, big), BG)
    img.paste(Image.new("RGBA", (big, big), FG), (0, 0), knight)
    if round_corners:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=big * 0.22, fill=255)
        img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


def main():
    res = ROOT / "app/android/app/src/main/res"
    for folder, px in {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
                       "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}.items():
        render(px, round_corners=True).save(res / folder / "ic_launcher.png")
    web = ROOT / "app/web"
    render(192, round_corners=True).save(web / "icons/Icon-192.png")
    render(512, round_corners=True).save(web / "icons/Icon-512.png")
    # маскируемые: значок меньше, фон до края (система сама скругляет)
    render(192, fill=0.5).save(web / "icons/Icon-maskable-192.png")
    render(512, fill=0.5).save(web / "icons/Icon-maskable-512.png")
    render(32, fill=0.8, round_corners=True).save(web / "favicon.png")
    render(512, round_corners=True).save(ROOT / "docs/app_icon.png")
    print("icons written")


if __name__ == "__main__":
    main()
