"""Curate exactly 20 transparent sheets from actual native renders; no photos.
Native common-scale views have fixed 102.31m framing, not per-model auto fit.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import json,sys
root=Path(sys.argv[1]);out=root/'sheets';out.mkdir(exist_ok=True)
views=['front','back','left','right','top','bottom','isometric']
models=json.loads((root/'manifest.json').read_text())['models']
def sheet(name,ids):
 rows=[(i,state) for i in ids for state in ['day','night','day-clay','day-silhouette']]
 s=Image.new('RGBA',(2100,180*len(rows)),(0,0,0,0));d=ImageDraw.Draw(s)
 for row,(i,state) in enumerate(rows):
  for col,view in enumerate(views):
   im=Image.open(root/'png'/state/f'{i}-{view}.png');im.thumbnail((290,145))
   x=col*300+(300-im.width)//2;y=row*180+25;s.alpha_composite(im,(x,y));d.text((col*300+8,row*180+5),f'{i} {state} {view}',fill=(80,85,110,255))
 s.save(out/f'{name}.png',optimize=True)
for m in models:
 if m.get('native_kind')!='assembly':sheet(m['id'],[m['id']])
for fleet in ['1000','2000']:sheet(f'formation-{fleet}',[f'taoyuan-airport-{fleet}-formation',f'taoyuan-airport-{fleet}-formation-far'])
s=Image.new('RGBA',(1400,1220),(0,0,0,0));d=ImageDraw.Draw(s)
for i,(fleet,view) in enumerate([('1000','left'),('2000','left'),('1000','isometric'),('2000','isometric')]):
 im=Image.open(root/'common'/f'taoyuan-airport-{fleet}-formation-{view}.png');s.alpha_composite(im,(0,i*300+20));d.text((12,i*300+4),f'{fleet} - shared metre scale, same camera and day light',fill=(70,75,100,255))
s.save(root/'overview.png',optimize=True)
print('curated',len(list(out.glob('*.png'))),'private PNG + 1 overview')
