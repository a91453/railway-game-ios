"""One compact Sanying review image from the common seven-view renders."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

run = Path(sys.argv[1])
out = Path(sys.argv[2])
sheet = Image.new("RGB", (1400, 830), "#eaedf2")
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 21)

def paste(name, view, box, label):
    image = Image.open(run / "png" / "day" / f"{name}-{view}.png").convert("RGBA")
    x, y, width, height = box
    image.thumbnail((width, height), Image.Resampling.LANCZOS)
    sheet.paste(image, (x + (width - image.width) // 2, y + (height - image.height) // 2), image)
    draw.text((x + 12, y + 8), label, font=font, fill="#28313d")

paste("sanying-a", "left", (10, 10, 1020, 395), "Car A · left")
paste("sanying-a", "front", (1040, 10, 350, 395), "Cab · front")
paste("sanying-formation", "isometric", (10, 415, 1380, 405), "Two-car formation")
sheet.save(out, optimize=True)
