from pathlib import Path
from PIL import Image,ImageDraw
import json,sys
r=Path(sys.argv[1]);(r/'sheets').mkdir(exist_ok=True)
models=json.loads((r/'manifest.json').read_text())['models']
views=['front','back','left','right','top','bottom','isometric']
for m in models:
 s=Image.new('RGBA',(2100,800),(0,0,0,0));d=ImageDraw.Draw(s)
 for row,state in enumerate(['day','night','day-clay','day-silhouette']):
  for col,v in enumerate(views):
   im=Image.open(r/'png'/state/f'{m["id"]}-{v}.png');im.load();im.thumbnail((290,165));s.alpha_composite(im,(col*300+5,row*200+30));d.text((col*300+6,row*200+6),state+' '+v,fill=(75,80,100,255))
 s.save(r/'sheets'/f'{m["id"]}.png',optimize=True)
s=Image.new('RGBA',(1600,1400),(0,0,0,0));d=ImageDraw.Draw(s)
d.text((20,10),'EMU700 | unaccepted study | units: fixed 20.8m / formation: 163.286m',fill=(60,65,90,255))
for row,role in enumerate(['emc','ep','et','em']):
 for col,suffix in enumerate(['','-far']):
  name='tra-emu700-'+role+suffix;im=Image.open(r/'png/day'/f'{name}-isometric.png');im.thumbnail((780,245));s.alpha_composite(im,(col*800+10,40+row*270));d.text((col*800+20,35+row*270),name,fill=(60,65,90,255))
for col,suffix in enumerate(['','-far']):
 im=Image.open(r/'png/day'/f'tra-emu700-739-740-formation{suffix}-left.png');im.thumbnail((780,220));s.alpha_composite(im,(col*800+10,1150))
s.save(r/'overview.png',optimize=True)
