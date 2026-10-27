# One overview image: python3 -I overview.py OUT overview.png [--time day|night|both] ID [ID ...]
# Each id's isometric view, in a grid (both lights: day above night).
import sys
from PIL import Image, ImageDraw, ImageFont
args = sys.argv[1:]
root, out = args[0], args[1]
rest = args[2:]
times = ['day']
if rest[:1] == ['--time']:
    times = ['day', 'night'] if rest[1] == 'both' else [rest[1]]
    rest = rest[2:]
cols, cell_w = 3, 600
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 16)
except OSError:
    font = ImageFont.load_default()
tiles = []
for i in rest:
    row = []
    for t in times:
        im = Image.open(f'{root}/png/{t}/{i}-isometric.png').convert('RGBA')
        im = im.resize((cell_w, int(im.height * cell_w / im.width)))
        row.append(im)
    tiles.append((i, row))
h = max(sum(im.height for im in row) for _, row in tiles) + 24
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new('RGB', (cols * cell_w, rows * h), (236, 238, 246))
d = ImageDraw.Draw(sheet)
for n, (i, row) in enumerate(tiles):
    x, y = n % cols * cell_w, n // cols * h
    d.text((x + 6, y + 4), i, fill=(29, 34, 48), font=font)
    y += 24
    for im in row:
        sheet.paste(im, (x, y), im)
        y += im.height
sheet.save(out)
