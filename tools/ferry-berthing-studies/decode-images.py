import hashlib,json,sys
from pathlib import Path
from PIL import Image
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for m in manifest['models']:
 assert len(m['views'])==14
 for view,name in m['views'].items():
  p=root/name
  with Image.open(p) as im:
   im.load();assert im.mode=='RGBA' and im.size==(512,512)
   box=im.getchannel('A').getbbox();assert box and min(box[:2])>=2 and max(box[2:])<=510,(name,box)
   assert im.getchannel('A').getextrema()==(0,255)
   h=hashlib.sha256(p.read_bytes()).hexdigest();assert h==m['image_metrics'][view]['sha256']
   assert p.stat().st_size<2*1024*1024
   rows.append(dict(file=name,alpha_bounds=box,sha256=h))
(root/'image-verification.json').write_text(json.dumps({'status':'VERIFIED','decoded_images':len(rows),'images':rows},indent=2)+'\n')
print('VERIFIED',len(rows),'RGBA PNGs: decoded, transparent, nonempty, unclipped, SHA, size')
