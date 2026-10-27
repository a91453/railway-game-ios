"""Flat-shaded orthographic render of the dumped E500 + 3 Chu-Kuang coaches (decision 430).

Reads set.json (per model: [x, y, z, nx, ny, nz, colour, glows] per vertex, x already placed along
the train, front at x = 0), writes three views and a combined sheet. Not part of the repository.
"""
import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

base = sys.argv[1]
models = json.load(open(base + "/set.json"))
V = np.array([row for m in models for row in m], dtype=np.float64)
pos = V[:, 0:3].reshape(-1, 3, 3)
nrm = V[:, 3:6].reshape(-1, 3, 3)[:, 0, :]
col = V[:, 6].astype(np.uint32).reshape(-1, 3)[:, 0]
glow = V[:, 7].reshape(-1, 3)[:, 0] > 0.5
rgb = np.stack([col & 255, (col >> 8) & 255, (col >> 16) & 255], axis=1).astype(np.float64)
print("triangles", len(pos), "glowing", int(glow.sum()))


def basis(az, el):
    az, el = np.radians(az), np.radians(el)
    c = np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])  # target -> eye
    f = -c
    r = np.cross(f, [0, 0, 1.0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return c, r, u


LIGHT = np.array([-0.45, 0.55, 0.70]); LIGHT /= np.linalg.norm(LIGHT)


def render(az, el, centre, half_height, size, ss=2, ground=True):
    W, H = size[0] * ss, size[1] * ss
    c, r, u = basis(az, el)
    scale = H / (2 * half_height)
    ctr = np.asarray(centre, dtype=np.float64)

    def project(p):
        d = p - ctr
        return np.stack([W / 2 + d @ r * scale, H / 2 - d @ u * scale, d @ c], axis=-1)

    img = np.zeros((H, W, 3)); zbuf = np.full((H, W), -1e9)
    # sky gradient
    top, bottom = np.array([200, 214, 232.]), np.array([238, 241, 246.])
    t = np.linspace(0, 1, H)[:, None, None]
    img[:] = top * (1 - t) + bottom * t
    glowmask = np.zeros((H, W))

    tris = [(pos, rgb, nrm, glow)]
    if ground:
        xs = (ctr[0] - 120, ctr[0] + 120); ys = (-14, 14)
        g = np.array([[[xs[0], ys[0], 0], [xs[1], ys[0], 0], [xs[1], ys[1], 0]],
                      [[xs[0], ys[0], 0], [xs[1], ys[1], 0], [xs[0], ys[1], 0]]], dtype=np.float64)
        gb = np.array([[[xs[0], -1.9, 0.02], [xs[1], -1.9, 0.02], [xs[1], 1.9, 0.02]],
                       [[xs[0], -1.9, 0.02], [xs[1], 1.9, 0.02], [xs[0], 1.9, 0.02]]])
        gn = np.array([[0, 0, 1.0]] * 2)
        tris.append((g, np.array([[150, 160, 140.]] * 2), gn, np.zeros(2, bool)))
        tris.append((gb, np.array([[124, 118, 112.]] * 2), gn, np.zeros(2, bool)))
    for P, C, N, G in tris:
        S = project(P)
        for i in range(len(P)):
            s = S[i]
            x0, x1 = int(max(0, np.floor(s[:, 0].min()))), int(min(W - 1, np.ceil(s[:, 0].max())))
            y0, y1 = int(max(0, np.floor(s[:, 1].min()))), int(min(H - 1, np.ceil(s[:, 1].max())))
            if x1 < x0 or y1 < y0:
                continue
            a, b, cc = s[0, :2], s[1, :2], s[2, :2]
            den = (b[1] - cc[1]) * (a[0] - cc[0]) + (cc[0] - b[0]) * (a[1] - cc[1])
            if abs(den) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            w0 = ((b[1] - cc[1]) * (gx - cc[0]) + (cc[0] - b[0]) * (gy - cc[1])) / den
            w1 = ((cc[1] - a[1]) * (gx - cc[0]) + (a[0] - cc[0]) * (gy - cc[1])) / den
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            depth = w0 * s[0, 2] + w1 * s[1, 2] + w2 * s[2, 2]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            win = inside & (depth > sub)
            if not win.any():
                continue
            n = N[i]
            facing = n @ c
            shade = 0.50 + 0.50 * max(0.0, n @ LIGHT)
            if facing < 0:  # seen from behind the face: darker
                shade *= 0.8
            colour = C[i] * shade
            if G[i]:
                colour = np.minimum(255, C[i] * 1.15 + 25)
            sub[win] = depth[win]
            img[y0:y1 + 1, x0:x1 + 1][win] = colour
            if G[i]:
                glowmask[y0:y1 + 1, x0:x1 + 1][win] = 1.0
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    gm = Image.fromarray((glowmask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6 * ss))
    gm2 = Image.fromarray((glowmask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2 * ss))
    arr = np.asarray(out).astype(np.float64)
    arr += np.asarray(gm).astype(np.float64)[:, :, None] * np.array([1.0, 0.18, 0.12]) * 1.2
    arr += np.asarray(gm2).astype(np.float64)[:, :, None] * np.array([0.9, 0.25, 0.2]) * 0.8
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    return out.resize(size, Image.LANCZOS)


xmin = pos[:, :, 0].min(); xmax = pos[:, :, 0].max()
print("train x", xmin, xmax)
tail_end = xmin
whole = render(az=125, el=14, centre=[(xmin + xmax) / 2, 0, 2.2], half_height=11.2, size=(1500, 460))
close = render(az=150, el=12, centre=[tail_end + 4.5, 0, 2.3], half_height=3.6, size=(760, 640))
rear = render(az=180, el=4, centre=[tail_end + 1.0, 0, 2.2], half_height=2.6, size=(560, 640))
whole.save(base + "/whole.png"); close.save(base + "/close.png"); rear.save(base + "/rear.png")

sheet = Image.new("RGB", (1500, 460 + 640 + 70), (255, 255, 255))
sheet.paste(whole, (0, 36))
sheet.paste(close, (0, 460 + 70))
sheet.paste(rear, (760 + 10, 460 + 70))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
except Exception:
    font = ImageFont.load_default()
d.text((8, 8), "E500CK + 3 Chu-Kuang coaches (decision 430), seen from behind-left; last coach lit", fill=(38, 44, 87), font=font)
d.text((8, 460 + 40), "tail end close-up", fill=(38, 44, 87), font=font)
d.text((770, 460 + 40), "straight from behind", fill=(38, 44, 87), font=font)
sheet.save(base + "/sheet.png")
