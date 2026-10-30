"""20 transparent PNGs per fleet; all input images come from native renders.
Run after review.mjs and common seven-view day/night rendering.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import sys
root=Path(sys.argv[1])
def panel(files,dest,title,columns=2,size=(600,330)):
 w,h=size;out=Image.new('RGBA',(w*columns,h*((len(files)+columns-1)//columns)+35));d=ImageDraw.Draw(out)
 d.text((15,8),title,fill='#262c57')
 for i,(label,p) in enumerate(files):
  im=Image.open(p);im.load();im.thumbnail((w-24,h-35));x=i%columns*w;y=i//columns*h+35
  out.alpha_composite(im,(x+(w-im.width)//2,y+20+(h-35-im.height)//2));d.text((x+12,y+3),label,fill='#262c57')
 dest.parent.mkdir(exist_ok=True,parents=True);out.save(dest,optimize=True)
for f in ['ankeng','danhai']:
 run=root/f;dest=run/'selected';dest.mkdir(exist_ok=True)
 def path(id,v,mode='color'):return run/'review'/mode/(id+'-'+v+'.png')
 for r in ['m1','m2','m3','m4','m5']:
  for far in [False,True]:
   id=f+'-lrt-'+r+('-far' if far else '')
   panel([(v,path(id,v))for v in ['front','left','right','top','isometric']],dest/(id+'.png'),id+' | fixed metres',columns=2)
 for far in [False,True]:
  suffix='-far' if far else '';id=f+'-lrt-formation'+suffix
  panel([(v,path(id,v))for v in ['front','left','right','top','isometric']],dest/(id+'.png'),id+' | 34.45m',columns=1,size=(1200,360))
  for mode in ['clay','silhouette']:
   panel([(v,path(id,v,mode))for v in ['front','left','top','isometric']],dest/(mode+suffix+'.png'),f+' '+mode+suffix,columns=1,size=(1200,330))
 id=f+'-lrt-formation'
 panel([(x,root/x/'review/color'/(x+'-lrt-formation-left.png')) for x in ['ankeng','danhai']],dest/'two-fleets-same-metres.png','Same 34.45m scale / camera / light',columns=1,size=(1200,280))
 panel([(r,path(f+'-lrt-'+r,'isometric'))for r in ['m1','m2','m3','m4','m5']],dest/'all-roles.png',f+' all independent roles',columns=2)
 panel([('near',path(id,'left')),('far',path(id+'-far','left'))],dest/'game-scale.png',f+' near/far at game scale',columns=1,size=(600,150))
 panel([(v,run/'png/night'/(id+'-'+v+'.png'))for v in ['front','left','isometric']],dest/'night.png',f+' night - native static light preview',columns=1,size=(1200,330))
 assert len(list(dest.glob('*.png')))==20
# One shared public overview; never a photograph composite.
public=Path(sys.argv[2])
panel([(f+' | 34.45m',root/f/'review/color'/(f+'-lrt-formation-isometric.png'))for f in ['ankeng','danhai']],public,'New Taipei LRT | Ankeng / Danhai | first delivery',columns=1,size=(1200,470))
