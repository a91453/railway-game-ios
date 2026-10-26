"""Decision 420's overview: a row a subject, a column a level (whole, the
game's 50 %, 25 % and 10 %, the far model made in code where there is one,
the box), each three-quarter from the front with its triangle count.

    python3 tools/mesh-lod-420/overview.py OUT overview.png [front|side]
"""
import json, sys
from PIL import Image, ImageDraw, ImageFont

root, out = sys.argv[1], sys.argv[2]
view = sys.argv[3] if len(sys.argv) > 3 else "front"
font = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 22)
small = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 18)
models = {m["id"]: m for m in json.load(open(f"{root}/manifest.json"))["models"]}
rows = [("太魯閣（決策 420 遠景）", "set-taroko"), ("區間車 EMU800（決策 420 遠景）", "set-emu800"),
        ("城際 EMU3000（決策 410）", "set-emu3000"), ("電力機車 E500", "set-E500CK"), ("高鐵 700T（決策 408）", "set-highSpeed"),
        ("路線公車", "bus-route")]
cols = [("完整", "100"), ("50 %", "50"), ("25 %", "25"), ("10 %", "10"), ("程式版遠景", "hand"), ("盒子", "box")]
W, H, pad, top = (300, 190, 10, 44) if view == "front" else (420, 90, 10, 44)
sheet = Image.new('RGB', (200 + len(cols) * (W + pad), top + len(rows) * (H + 30)), (236, 238, 246))
d = ImageDraw.Draw(sheet)
for c, (label, _) in enumerate(cols):
    d.text((200 + c * (W + pad), 10), label, fill='black', font=font)
for r, (label, key) in enumerate(rows):
    y = top + r * (H + 30)
    d.text((8, y + H // 2 - 12), label, fill='black', font=font)
    for c, (_, tag) in enumerate(cols):
        name = f"{key}-{tag}"
        if name not in models:
            continue
        im = Image.open(f"{root}/png/{name}-{view}.png").convert('RGBA')
        im = im.crop(im.getbbox())
        s = min((W - 10) / im.width, (H - 6) / im.height)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
        cell = Image.new('RGBA', (W, H), 'white')
        cell.alpha_composite(im, ((W - im.width) // 2, (H - im.height) // 2))
        x = 200 + c * (W + pad)
        sheet.paste(cell, (x, y), cell)
        d.text((x + 4, y + H + 4), f"{models[name]['triangles']:,} 個三角形", fill=(60, 60, 60), font=small)
sheet.save(out, optimize=True)
print(sheet.size)
