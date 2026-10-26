"""Decision 422's comparison: each train's head car near, the new far and
the old far, three-quarter from the front and from the side, at the size
it has on an iPhone's screen (1,179 pixels tall, the map's 35° lens) 250,
500 and 750 m away, each pixel then drawn 3 × 3; and the same cars large.

    python3 tools/hsr-far-422/distance.py RENDERS overview.png

RENDERS is the folder `tools/mesh-lod-420/render.mjs` drew, its models
named `<train>-<unit>-<near|newfar|oldfar>` (README.md).
"""
import math, sys
from PIL import Image, ImageDraw, ImageFont

root, out = sys.argv[1], sys.argv[2]
font = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 22)
small = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 17)
trains = [("700t", "高鐵 700T"), ("n700", "N700S-G")]
kinds = [("near", "近景"), ("newfar", "新遠景（決策 422）"), ("oldfar", "舊遠景")]
pixels_per_metre = lambda d: 1179 / (2 * d * math.tan(math.radians(17.5)))
# The head car's length across the picture: all of it from the side, its
# length and width as the three-quarter view turns them (0.8 and 0.6).
across = {"side": 25.3, "front": 0.8 * 25.3 + 0.6 * 3.4}
zoom, pad = 3, 14

def cell(train, kind, view, metres):
    image = Image.open(f"{root}/png/{train}-head-{kind}-{view}.png").convert("RGBA")
    image = image.crop(image.getbbox())
    width = max(1, round(across[view] * pixels_per_metre(metres)))
    height = max(1, round(image.height * width / image.width))
    small_image = image.resize((width, height), Image.LANCZOS)
    return small_image.resize((width * zoom, height * zoom), Image.NEAREST)

blocks = []
for train, title in trains:
    rows = []
    for metres in (250, 500, 750):
        for view in ("front", "side"):
            rows.append((f"{metres} m {'斜前' if view == 'front' else '側面'}", [cell(train, k, view, metres) for k, _ in kinds]))
    large = []
    for k, _ in kinds:
        image = Image.open(f"{root}/png/{train}-head-{k}-front.png").convert("RGBA")
        image = image.crop(image.getbbox())
        large.append(image.resize((560, round(image.height * 560 / image.width)), Image.LANCZOS))
    rows.append(("近看", large))
    blocks.append((title, rows))

label_w = 150
col_w = max(max(i.width for _, r in rows for i in [r[c]]) for _, rows in blocks for c in range(3)) + pad
row_h = lambda r: max(i.height for i in r) + pad
height = sum(44 + 34 + sum(row_h(r) for _, r in rows) for _, rows in blocks)
sheet = Image.new("RGB", (label_w + 3 * col_w, height), (236, 238, 246))
draw = ImageDraw.Draw(sheet)
y = 0
for title, rows in blocks:
    draw.text((10, y + 10), title, fill=(30, 30, 40), font=font)
    y += 44
    for c, (_, name) in enumerate(kinds):
        draw.text((label_w + c * col_w, y + 4), name, fill=(60, 60, 80), font=small)
    y += 34
    for name, images in rows:
        draw.text((10, y + 8), name, fill=(60, 60, 80), font=small)
        for c, image in enumerate(images):
            sheet.paste(image, (label_w + c * col_w, y), image)
        y += row_h(images)
sheet.save(out)
