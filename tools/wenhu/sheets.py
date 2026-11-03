from pathlib import Path
from PIL import Image,ImageDraw
import json,sys
root=Path(sys.argv[1]);out=root/'sheets';out.mkdir(exist_ok=True)
views=['front','back','left','right','top','bottom','isometric']
for fleet in ['val256','apm256']:
 for role in ['a','b','formation']:
  ids=[f'wenhu-{fleet}-{role}',f'wenhu-{fleet}-{role}-far']
  rows=[(i,s) for i in ids for s in ['day','night','clay','silhouette']]
  sheet=Image.new('RGBA',(2100,1440),(0,0,0,0));d=ImageDraw.Draw(sheet)
  for row,(i,state) in enumerate(rows):
   for col,v in enumerate(views):
    im=Image.open(root/'png'/state/f'{i}-{v}.png');im.thumbnail((290,145));x=col*300+(300-im.width)//2;y=row*180+26
    sheet.alpha_composite(im,(x,y));d.text((col*300+6,row*180+4),f'{i} {state} {v}',fill=(60,65,85,255))
  sheet.save(out/f'{fleet}-{role}.png',optimize=True)
sheet=Image.new('RGBA',(1600,1400),(0,0,0,0));d=ImageDraw.Draw(sheet)
d.text((25,15),'Wenhu VAL256 / APM256 | DRAFT UNVERIFIED | shared metre frames',fill=(60,65,85,255))
for row,(role,v) in enumerate([('a','front'),('a','isometric'),('formation','left'),('formation','isometric')]):
 for col,f in enumerate(['val256','apm256']):
  im=Image.open(root/'png/day'/f'wenhu-{f}-{role}-{v}.png');im.thumbnail((770,310));sheet.alpha_composite(im,(col*800+(800-im.width)//2,50+row*330));d.text((col*800+20,38+row*330),f'{f} {role} {v}',fill=(60,65,85,255))
sheet.save(root/'overview.png',optimize=True)

# Optional true previous producer comparison. Both columns use the renderer's
# identical metre frame and light; the previous candidate was not accepted.
if (root/'comparison').exists():
 for fleet in ['val256','apm256']:
  sheet=Image.new('RGBA',(1600,1700),(0,0,0,0));d=ImageDraw.Draw(sheet)
  d.text((20,8),'Before 91a31f08 (UNACCEPTED) / revised native geometry | same metre camera and light',fill=(60,65,85,255))
  for row,(role,v) in enumerate([('a','front'),('a','isometric'),('a','bottom'),('a','top'),('formation','left')]):
   for col,tag in enumerate(['before','after']):
    im=Image.open(root/'comparison'/f'{tag}-wenhu-{fleet}-{role}-{v}.png');im.thumbnail((770,290));x=col*800+(800-im.width)//2;y=40+row*330
    sheet.alpha_composite(im,(x,y+20));d.text((col*800+20,y),f'{tag} {fleet} {role} {v}',fill=(60,65,85,255))
  sheet.save(out/f'{fleet}-comparison.png',optimize=True)
