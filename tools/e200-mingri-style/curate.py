"""Curate 20 transparent sheets, from final native fixed-camera renders only.
RUN FIXED CLEAN_PRODUCER_CHECKOUT PRODUCER
"""
import json,sys,shutil
from pathlib import Path
from PIL import Image,ImageDraw
run,fixed,repo=map(Path,sys.argv[1:4]);producer=sys.argv[4];dst=run/'selected';dst.mkdir(exist_ok=True)
views=['front','left','top','isometric'];ids=['e200mingri-style-'+r+s for s in ['', '-far'] for r in ['head','car','tail']]+['mingri-style-formation','mingri-style-formation-far']
def sheet(name,items,labels,cols=2):
 w,h=640,250;rows=(len(items)+cols-1)//cols;im=Image.new('RGBA',(cols*w,rows*h),(0,0,0,0));d=ImageDraw.Draw(im)
 for i,(path,label) in enumerate(zip(items,labels)):
  q=Image.open(path).convert('RGBA');q.thumbnail((w-20,h-36));x=(i%cols)*w+(w-q.width)//2;y=(i//cols)*h+30+(h-36-q.height)//2;im.alpha_composite(q,(x,y));d.text(((i%cols)*w+12,(i//cols)*h+10),label,fill=(45,50,65,255))
 p=dst/(name+'.png');im.save(p,optimize=True);return 'selected/'+p.name
pngs=[]
for id in ids:
 pngs.append(sheet(id,[fixed/(id+'-color-'+v+'-after.png') for v in views],[id+' / '+v for v in views]))
for id in ids:
 pngs.append(sheet(id+'-comparison',[fixed/(id+'-color-'+v+'-'+t+'.png') for v in ['left','isometric'] for t in ['before','after']],[v+' / '+t for v in ['left','isometric'] for t in ['before','after']]))
for material in ['clay','silhouette']:
 pngs.append(sheet('all-'+material,[fixed/(id+'-'+material+'-'+v+'-after.png') for id in ids for v in ['front','left']], [id+' / '+v for id in ids for v in ['front','left']],cols=4))
for id in ids[-2:]:pngs.append(sheet(id+'-night',[run/'png/night'/(id+'-'+v+'.png') for v in views],[id+' night / '+v for v in views]))
assert len(pngs)==20
# Smaller public overview: native comparison, original and variant share camera/metres/light.
sheet('overview',[fixed/(ids[-2]+'-color-'+v+'-'+t+'.png') for v in ['left','isometric'] for t in ['before','after']],['original / side','Mingri style / side','original / oblique','Mingri style / oblique'])
source=json.loads((repo/'docs/art/e200-mingri-style/source-record.json').read_text());source['public_use']='Only original project-authored models/previews; reference photographs are observation-only and excluded.'
(run/'source-record.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
status={'asset':{'status':'UNVERIFIED','evidence':'See verification.json; final delivered viewer and producer rebuild must run before VERIFIED.'},'appearance':{'status':'UNVERIFIED','accepted_producer':None,'evidence':'First livery revision. Prompt authorizes production, not acceptance. Original producer acceptance provenance unresolved.'},'integration':{'status':'UNVERIFIED','evidence':'studies only; no independent player livery mechanism; no operational changes or resident models.'},'device':{'status':'UNVERIFIED','evidence':'No new iOS Simulator, physical-device Metal, FPS, memory or animation verification; Linux WebGL is separate.'}}
(run/'status.json').write_text(json.dumps(status,indent=2)+'\n')
spec={'repo':str(repo.resolve()),'producer':producer,'rebuild':'tools/train-models/run.sh OUT --ids e200mingri-style-head,e200mingri-style-car,e200mingri-style-tail,e200mingri-style-head-far,e200mingri-style-car-far,e200mingri-style-tail-far,set-E200CK-head,set-E200CK-car,set-E200CK-tail --assembly-spec tools/e200-mingri-style/assembly.json; node tools/train-models/package.mjs OUT','sources':'source-record.json','status':'status.json','license_files':[],'pngs':pngs}
(run/'delivery.json').write_text(json.dumps(spec,indent=2)+'\n')
# Keep the complete original comparison run in temporary storage; delivery has only new models.
m=json.loads((run/'manifest.json').read_text());m['models']=[x for x in m['models'] if x['id'] in ids];m['model_count']=len(m['models']);m['producer_commit']=producer
(run/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print('Curated 20 private PNG sheets plus one public overview, eight final native/GLB records')
