from pathlib import Path
from PIL import Image,ImageDraw
import sys,shutil
root=Path(sys.argv[1]);dest=root/'selected';dest.mkdir(exist_ok=True)
ids=['tra-r200-r216-locomotive','tra-r200-r216-locomotive-far']
views=['front','back','left','right','top','bottom','isometric']
for id in ids:
 for v in views:shutil.copyfile(root/'review/color'/f'{id}-{v}.png',dest/f'{id}-{v}.png')
 for v in ['front','isometric']:shutil.copyfile(root/'review/clay'/f'{id}-{v}.png',dest/f'{id}-clay-{v}.png')
def panel(items,path,title,w=1200,h=350):
 out=Image.new('RGBA',(w,h*len(items)+45));d=ImageDraw.Draw(out);d.text((12,10),title,fill='#262c57')
 for i,(label,p) in enumerate(items):
  im=Image.open(p);im.thumbnail((w-30,h-28));x=(w-im.width)//2;y=45+i*h;out.alpha_composite(im,(x,y+22));d.text((12,y+4),label,fill='#262c57')
 out.save(path,optimize=True)
panel([(id+' '+v,root/'review/silhouette'/f'{id}-{v}.png')for id in ids for v in ['front','left','top','isometric']],dest/'silhouette.png','R200 near/far | same metre camera',h=250)
before=Path(sys.argv[3]) if len(sys.argv)>3 else None
items=[(id,root/'review/color'/f'{id}-left.png')for id in ids]
if before:items=[('R1 65464b23 unaccepted',before/'review/color'/f'{ids[0]}-left.png')]+items
panel(items,dest/'game-scale.png','R200 common metre scale | true R1 / revised near-far',w=600,h=160)
if before:
 public=[]
 for v in ['isometric','left','front']:
  public.extend([('R1 65464b23 (unaccepted) '+v,before/'review/color'/f'{ids[0]}-{v}.png'),('R2 revised near '+v,root/'review/color'/f'{ids[0]}-{v}.png')])
 panel(public,Path(sys.argv[2]),'R200 true revision comparison | same metres, camera and lighting',w=1000,h=270)
else:
 panel([(id+' '+v,root/'review/color'/f'{id}-{v}.png')for v in ['isometric','left','front']for id in ids],Path(sys.argv[2]),'R216 ordinary white/navy | near/far | common metres | UNACCEPTED',w=1000,h=270)
assert len(list(dest.glob('*.png')))==20
