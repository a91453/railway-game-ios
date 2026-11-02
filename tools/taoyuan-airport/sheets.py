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
# One public overview: true previous producer versus this revision. Every pair
# uses the same metre camera/light; source-photo pixels are never included.
s=Image.new('RGBA',(1600,1860),(0,0,0,0));d=ImageDraw.Draw(s)
d.text((20,8),'Airport MRT | previous e1139b6 (UNACCEPTED) / revised native geometry',fill=(60,65,90,255))
for row,(role,view) in enumerate([('dmc1','front'),('dme1','isometric'),('dmb','left')]):
 for col,tag in enumerate(['before','after']):
  p=root/'comparison'/f'{tag}-taoyuan-airport-{role}-{view}.png'
  if not p.exists():continue
  im=Image.open(p);im.thumbnail((780,350));x=col*800+(800-im.width)//2;y=35+row*390
  s.alpha_composite(im,(x,y+20));d.text((col*800+20,y),f'{tag} | {role} {view} | identical metre framing',fill=(60,65,90,255))
for row,fleet in enumerate(['1000','2000']):
 for col,tag in enumerate(['before','after']):
  p=root/'comparison'/f'{tag}-taoyuan-airport-{fleet}-formation-left.png'
  if not p.exists():continue
  im=Image.open(p);im.thumbnail((780,220));y=1220+row*290
  s.alpha_composite(im,(col*800+(800-im.width)//2,y+25));d.text((col*800+20,y),f'{tag} | {fleet} full formation | shared 102.31m framing',fill=(60,65,90,255))
s.save(root/'overview.png',optimize=True)
print('curated',len(list(out.glob('*.png'))),'private PNG + 1 overview')
