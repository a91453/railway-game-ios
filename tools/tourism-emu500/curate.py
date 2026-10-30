"""Select native previews only: <=20 private PNGs/fleet + one public overview."""
from pathlib import Path
from PIL import Image,ImageDraw
import sys
root=Path(sys.argv[1])
def panel(files,dest,title,columns=2,size=(600,310)):
 w,h=size;out=Image.new('RGBA',(w*columns,h*((len(files)+columns-1)//columns)+35));d=ImageDraw.Draw(out);d.text((15,8),title,fill='#262c57')
 for i,(label,p) in enumerate(files):
  im=Image.open(p);im.load();im.thumbnail((w-24,h-35));x=i%columns*w;y=i//columns*h+35
  out.alpha_composite(im,(x+(w-im.width)//2,y+20+(h-35-im.height)//2));d.text((x+12,y+3),label,fill='#262c57')
 dest.parent.mkdir(exist_ok=True,parents=True);out.save(dest,optimize=True)
for f in ['haifeng','shanlan']:
 run=root/f;dest=run/'selected';dest.mkdir(exist_ok=True)
 def path(id,v,mode='color'):return run/'review'/mode/(id+'-'+v+'.png')
 for role in ['emc','ep','et','em']:
  for far in [False,True]:
   id=f+'-emu500-'+role+('-far' if far else '')
   panel([(v,path(id,v))for v in ['front','left','right','top','isometric']],dest/(id+'.png'),id+' | common metres')
 for far in [False,True]:
  suffix='-far' if far else '';id=f+'-emu500-formation'+suffix
  panel([(v,path(id,v))for v in ['front','left','right','top','isometric']],dest/(id+'.png'),id+' | 81.32m centre-pitch envelope',columns=1,size=(1200,330))
  for mode in ['clay','silhouette']:
   panel([(v,path(id,v,mode))for v in ['front','left','top','isometric']],dest/(mode+suffix+'.png'),f+' '+mode+suffix,columns=1,size=(1200,310))
  panel([(r,path(f+'-emu500-'+r+suffix,'isometric','clay'))for r in ['emc','ep','et','em']],dest/('roles-clay'+suffix+'.png'),f+' roles clay',columns=2)
  panel([(r,path(f+'-emu500-'+r+suffix,'isometric','silhouette'))for r in ['emc','ep','et','em']],dest/('roles-silhouette'+suffix+'.png'),f+' roles silhouette',columns=2)
 id=f+'-emu500-formation'
 panel([('near',path(id,'left')),('far',path(id+'-far','left'))],dest/'game-scale.png',f+' near/far game scale',columns=1,size=(600,150))
 panel([(v,run/'png/night'/(id+'-'+v+'.png'))for v in ['front','left','isometric']],dest/'night.png',f+' static night preview; no operating lights integration',columns=1,size=(1200,310))
 assert len(list(dest.glob('*.png')))==20
files=[]
for f,label in [('baseline','EMU500 conversion baseline (not an accepted previous tourism version)'),('haifeng','Haifeng EMU573'),('shanlan','Shanlan EMU583')]:
 id='emu500-formation' if f=='baseline' else f+'-emu500-formation'
 files.extend([(label+' | '+v,root/f/'review/color'/(id+'-'+v+'.png'))for v in ['isometric','left','front']])
panel(files,Path(sys.argv[2]),'Native EMU500 conversions | same metre camera and light | first delivery',columns=3,size=(560,300))
