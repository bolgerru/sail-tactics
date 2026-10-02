"""Generates icon.png next to the Godot project (1024x1024, RGB, no alpha - App Store requirement).
Run from the repo root: python godot/tools/make_icon.py"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersample
img = Image.new("RGB", (S, S))
px = img.load()
top, bot = (30, 150, 220), (0, 78, 140)
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    d.line([(0, y), (S, y)], fill=c)

# Soft dark gust patch + light water streaks
ov = Image.new("RGBA", (S, S), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
od.ellipse([S * 0.05, S * 0.50, S * 0.70, S * 0.98], fill=(0, 30, 80, 70))
ov = ov.filter(ImageFilter.GaussianBlur(S * 0.06))
img.paste(ov, (0, 0), ov)

d = ImageDraw.Draw(img, "RGBA")
import random
random.seed(7)
for _ in range(70):
    x, y = random.uniform(0, S), random.uniform(0, S)
    l = random.uniform(S * 0.012, S * 0.03)
    d.line([(x, y), (x, y + l)], fill=(255, 255, 255, random.randint(18, 50)), width=int(S * 0.003))

# Finish line (dashed) near the top
dash = S * 0.055
x = 0
y = S * 0.11
while x < S:
    d.rectangle([x, y, x + dash, y + S * 0.012], fill=(255, 68, 68, 230))
    x += dash * 2

# Boat: same shape as the game, heading tilted like a close-hauled tack
r = S * 0.21
cx, cy = S * 0.53, S * 0.46
h = math.radians(20)
c, s = math.cos(h), math.sin(h)

def tf(px_, py_):
    return (cx + px_ * c - py_ * s, cy + px_ * s + py_ * c)

# Wake behind the boat: fading V made of short segments
for side in (-1, 1):
    N = 70
    for i in range(N):
        t0, t1 = i / N, (i + 1) / N
        pts = []
        for t in (t0, t1):
            back = r * 0.9 + t * r * 3.4
            spread = r * 0.30 + t * r * 0.75
            pts.append(tf(side * spread, back))
        alpha = int(150 * (1 - t0) ** 1.4)
        d.line(pts, fill=(255, 255, 255, alpha), width=int(S * 0.010))

# Drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
hull_local = [(0, -r), (r * 0.7, r), (0, r * 0.8), (-r * 0.7, r)]
sd.polygon([(a + S * 0.012, b + S * 0.018) for a, b in map(lambda p: tf(*p), hull_local)], fill=(0, 20, 60, 120))
shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.012))
img.paste(shadow, (0, 0), shadow)

d = ImageDraw.Draw(img, "RGBA")
hull = [tf(*p) for p in hull_local]
d.polygon(hull, fill=(255, 204, 0), outline=(51, 51, 51))
d.line(hull + [hull[0]], fill=(51, 51, 51), width=int(S * 0.006), joint="curve")

sail = [tf(0, -r * 0.55), tf(0, r * 0.55), tf(r * 0.62, r * 0.55)]
d.polygon(sail, fill=(255, 255, 255))
d.line(sail + [sail[0]], fill=(51, 51, 51), width=int(S * 0.006), joint="curve")

out = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
out.save("godot/icon.png")
print("saved", out.size, out.mode)
