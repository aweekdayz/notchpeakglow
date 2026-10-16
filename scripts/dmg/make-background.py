"""Draw the background of the installer disk image (660 x 400 points, plus a @2x version).

Needs numpy and Pillow. The mid-tone slate keeps Finder's file names readable in both light
and dark appearance (Finder draws them in black or white and cannot be told otherwise).
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 660, 400
OUT = os.path.dirname(os.path.abspath(__file__))
FONTS = ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"]


def font(size):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def render(scale):
    w, h = W * scale, H * scale
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # Slate gradient, lighter at the top.
    top, bottom = np.array([0.55, 0.59, 0.69]), np.array([0.34, 0.37, 0.46])
    t = (yy / h)[..., None]
    img = top * (1 - t) + bottom * t

    # The notch and its glow, as in the app icon, small at the top centre.
    cx = w / 2
    nw, nh, r = 150 * scale, 40 * scale, 16 * scale
    qx = np.abs(xx - cx) - nw / 2 + r
    qy = np.abs(yy - (nh / 2 - 200 * scale)) - (nh / 2 + 200 * scale) + r
    sd = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - r
    d = np.maximum(sd, 0)
    stops = np.array([[0.18, 0.36, 1.0], [0.10, 0.78, 1.0], [0.22, 0.92, 0.46], [0.99, 0.88, 0.28]], np.float32)
    u = np.clip((xx - (cx - nw / 2 - 30 * scale)) / (nw + 60 * scale), 0, 1) * 3
    i = np.minimum(u.astype(int), 2)
    f = (u - i)[..., None]
    f = f * f * (3 - 2 * f)
    colour = stops[i] * (1 - f) + stops[i + 1] * f
    env = 0.7 * np.exp(-d / (3 * scale)) + 0.9 * np.exp(-d / (16 * scale)) + 0.35 * np.exp(-d / (50 * scale))
    a = np.clip(env * 0.9, 0, 0.95)[..., None] * (sd > 0)[..., None]
    img = img * (1 - a) + colour * a
    img = np.where((sd <= 0)[..., None], np.array([0.01, 0.01, 0.015]), img)

    im = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(im, "RGBA")
    # An arrow between the two icons.
    ay = 195 * scale
    x0, x1 = 285 * scale, 375 * scale
    d.line([(x0, ay), (x1 - 4 * scale, ay)], fill=(255, 255, 255, 215), width=int(5 * scale))
    d.polygon([(x1 + 8 * scale, ay), (x1 - 12 * scale, ay - 15 * scale), (x1 - 12 * scale, ay + 15 * scale)],
              fill=(255, 255, 255, 215))
    text = "Drag PeakGlow to Applications"
    f1 = font(15 * scale)
    tw = d.textlength(text, font=f1)
    d.text(((w - tw) / 2, 336 * scale), text, font=f1, fill=(255, 255, 255, 235))
    return im.convert("RGB")


render(1).save(os.path.join(OUT, "background.png"), optimize=True)
render(2).save(os.path.join(OUT, "background@2x.png"), optimize=True)
print("wrote background.png and background@2x.png")
