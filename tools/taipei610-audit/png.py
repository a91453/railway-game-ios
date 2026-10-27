import json,sys,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());rows=[]
for p in list((root/'png').rglob('*.png'))+list((root/'details').glob('*.png')):
 im=Image.open(p);im.load();assert im.mode=='RGBA',(p,im.mode)
 box=im.getchannel('A').getbbox();assert box is not None
 if p.parent.name!='details' and not p.name.startswith('viewer-'):
  assert box[0]>0 and box[1]>0 and box[2]<im.width and box[3]<im.height,(p,'clipped')
  assert im.getchannel('A').getextrema()==(0,255),(p,'no transparency')
 rows.append({'file':str(p.relative_to(root)),'size':im.size,'bbox':box,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for a in m['models']:
 for key in ['native','glb']:a[key+'_sha256']=hashlib.sha256((root/a[key]).read_bytes()).hexdigest()
 a['view_metrics']={v:next(r for r in rows if r['file']==p) for v,p in a['views'].items()}
(root/'manifest.json').write_text(json.dumps(m,indent=2))
(root/'png-verification.json').write_text(json.dumps({'decoder':'Pillow','images':rows,'checks':['full decode','RGBA','nonempty','seven full views alpha and no boundary contact'],'detail_crops':'explicit filenames; contain partial train by design'},indent=2))
# Pages have background and margins; all local crops are labelled.
font=None
names=['taipei610-a-isometric.png','taipei610-formation-isometric.png','taipei610-a-left.png','taipei610-a-front.png']
page=Image.new('RGB',(1400,1180),'#eceef6');d=ImageDraw.Draw(page);d.text((30,20),'Taipei Metro 610 | phase one | first independent native model | NOT USER ACCEPTED',fill='#262c57')
for i,n in enumerate(names):
 im=Image.open(root/'png/day'/n);im.thumbnail((1300,250));x=40;y=65+i*275;page.paste(im,(x,y),im);d.text((40,y),n,fill='#262c57')
page.save(root/'overview.png')
for folder,files,title in [('details',list((root/'details').glob('detail-crop-*.png')),'DETAIL CROP - partial vehicle'),('details',list((root/'details').glob('same-metre-scale-*.png')),'SAME METRE SCALE - accepted E500 v3 / EMU3000 v5')]:
 page=Image.new('RGB',(1300,380*len(files)+50),'#eceef6');d=ImageDraw.Draw(page);d.text((30,15),title,fill='#262c57')
 for i,p in enumerate(files):
  im=Image.open(p);im.thumbnail((1200,330));page.paste(im,(40,60+i*380),im);d.text((40,45+i*380),p.stem,fill='#262c57')
 page.save(root/('detail-crops-page.png' if title.startswith('DETAIL') else 'same-scale-style-page.png'))
print('VERIFIED PNG',len(rows))
