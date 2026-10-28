from pathlib import Path
from PIL import Image
import sys,json
root=Path(sys.argv[1]);paths=list((root/'png').rglob('*.png'))
for p in paths:
 with Image.open(p) as im:
  im.load();assert im.mode=='RGBA',p
  a=im.getchannel('A');box=a.getbbox();assert box and a.getextrema()==(0,255),p
  assert box[0]>0 and box[1]>0 and box[2]<im.width and box[3]<im.height,('clipped',p)
print(json.dumps({'status':'VERIFIED','complete_png_decodes':len(paths),'RGBA_transparent_unclipped':True}))
