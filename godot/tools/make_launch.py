"""Generates the launch-screen logo (godot/assets/launch@2x.png and @3x.png): the yellow boat on a
transparent background, shown centred on the ocean-blue launch screen.
Run from the repo root: python godot/tools/make_launch.py"""
import math
import pathlib
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parents[1] / "assets"
OUT.mkdir(exist_ok=True)


def render(px):
    S = px * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    r = S * 0.34
    cx, cy = S * 0.5, S * 0.52
    h = math.radians(20)
    c, s = math.cos(h), math.sin(h)

    def tf(x, y):
        return (cx + x * c - y * s, cy + x * s + y * c)

    hull = [tf(0, -r), tf(r * 0.7, r), tf(0, r * 0.8), tf(-r * 0.7, r)]
    d.polygon(hull, fill=(255, 204, 0, 255))
    d.line(hull + [hull[0]], fill=(51, 51, 51, 255), width=max(2, int(S * 0.012)), joint="curve")
    sail = [tf(0, -r * 0.55), tf(0, r * 0.55), tf(r * 0.62, r * 0.55)]
    d.polygon(sail, fill=(255, 255, 255, 255))
    d.line(sail + [sail[0]], fill=(51, 51, 51, 255), width=max(2, int(S * 0.012)), joint="curve")
    return img.resize((px, px), Image.LANCZOS)


for scale in (2, 3):
    render(120 * scale).save(OUT / ("launch@%dx.png" % scale))
    print("wrote launch@%dx.png" % scale)
