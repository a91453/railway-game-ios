"""Composite actual final renders for four backgrounds, size, blur and grayscale review."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter,ImageOps
import sys
root=Path(sys.argv[1]); source=Image.open(root/'previews/duplex-locomotive-hero.png').convert('RGBA');source=source.crop(source.getbbox())
canvas=Image.new('RGB',(1280,1200),'#ECEEF6');draw=ImageDraw.Draw(canvas)
for row,(name,color) in enumerate([('map light','#dce9da'),('map dark','#263c40'),('panel light','#ffffff'),('panel dark','#262c57')]):
    y=row*300;draw.rectangle((0,y,1280,y+295),fill=color);text='white' if 'dark' in name else '#262c57';draw.text((10,y+10),name,fill=text)
    x=150
    for size in [256,120,64,44,28]:
        image=source.copy();image.thumbnail((size,size));canvas.paste(image,(x,y+55),image);draw.text((x,y+30),str(size),fill=text);x+=size+22
    for label,image in [('blur',source.filter(ImageFilter.GaussianBlur(9))),('gray',ImageOps.grayscale(source).convert('RGBA'))]:
        if label=='gray':image.putalpha(source.getchannel('A'))
        image.thumbnail((170,120));canvas.paste(image,(x,y+55),image);draw.text((x,y+30),label,fill=text);x+=180
canvas.save(root/'previews/style-background-size-check.png')
