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
s=Image.new('RGBA',(1600,1900),(0,0,0,0));d=ImageDraw.Draw(s)
d.text((20,10),'EMU700 | unaccepted study | units: fixed 20.8m / formation: 163.286m',fill=(60,65,90,255))
for col,tag in enumerate(['before','after']):
 im=Image.open(r/'mouth'/f'{tag}-color-front.png');im.load();im.thumbnail((400,400));s.alpha_composite(im,(col*800+200,55));d.text((col*800+20,35),'553b3a22 USER REJECTED' if tag=='before' else 'CURRENT: not user accepted',fill=(60,65,90,255))
for row,role in enumerate(['emc','ep','et','em']):
 for col,suffix in enumerate(['','-far']):
  name='tra-emu700-'+role+suffix;im=Image.open(r/'png/day'/f'{name}-isometric.png');im.thumbnail((780,245));s.alpha_composite(im,(col*800+10,500+row*270));d.text((col*800+20,495+row*270),name,fill=(60,65,90,255))
for col,suffix in enumerate(['','-far']):
 im=Image.open(r/'png/day'/f'tra-emu700-739-740-formation{suffix}-left.png');im.thumbnail((780,220));s.alpha_composite(im,(col*800+10,1610))
s.save(r/'overview.png',optimize=True)

# One curated comparison sheet; raw reference photographs are never embedded.
s=Image.new('RGBA',(1600,1690),(0,0,0,0));d=ImageDraw.Draw(s)
d.text((10,10),'Fixed metre cab-detail crops / same light; full native cars in role sheets',fill=(60,65,90,255))
columns=[('before','','553b3a22 REJECTED near'),('after','','current near UNVERIFIED'),('before','-far','553b3a22 REJECTED far'),('after','-far','current far UNVERIFIED')]
rows=[('color','front'),('clay','front'),('silhouette','front'),('color','isometric')]
for col,(tag,suffix,label) in enumerate(columns):
 d.text((col*400+8,32),label,fill=(60,65,90,255))
 for row,(state,view) in enumerate(rows):
  im=Image.open(r/'mouth'/f'{tag}{suffix}-{state}-{view}.png');im.load();im.thumbnail((380,380));s.alpha_composite(im,(col*400+10,65+row*400));d.text((col*400+10,50+row*400),state+' '+view,fill=(60,65,90,255))
s.save(r/'sheets'/'tra-emu700-mouth-before-after.png',optimize=True)
