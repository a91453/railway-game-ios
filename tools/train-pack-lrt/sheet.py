import sys
from PIL import Image, ImageDraw, ImageFont
out, rows = sys.argv[2], sys.argv[3:]
# each row: label=file,file,...
font = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 22)
imgs = []
for row in rows:
    label, files = row.split('=', 1)
    ims = [Image.open(sys.argv[1] + '/png/' + f + '.png').convert('RGBA') for f in files.split(',')]
    h = 300
    ims = [im.resize((int(im.width * h / im.height), h)) for im in ims]
    w = sum(im.width for im in ims) + 10 * (len(ims) - 1)
    canvas = Image.new('RGBA', (w, h + 34), 'white')
    d = ImageDraw.Draw(canvas); d.text((6, 4), label, fill='black', font=font)
    x = 0
    for im in ims: canvas.alpha_composite(im, (x, 34)); x += im.width + 10
    imgs.append(canvas)
W = max(i.width for i in imgs); H = sum(i.height for i in imgs) + 8 * len(imgs)
sheet = Image.new('RGB', (W, H), (236, 238, 246)); y = 0
for i in imgs: sheet.paste(i, (0, y), i); y += i.height + 8
sheet.save(out)
