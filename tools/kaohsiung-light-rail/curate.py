"""20 transparent native-render sheets per fleet and one combined public sheet."""
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
run,fixed,repo=map(Path,sys.argv[1:4]);producer=sys.argv[4]
prior=Path(sys.argv[5]) if len(sys.argv)>5 else None
prior_producer=sys.argv[6] if prior else None
if prior: assert len(prior_producer)==40
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',19)
small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15)
views=['front','left','top','isometric']
roles={'caf':['c1','s1','r','s2','c2'],'citadis':['m1','sc1','np','sc2','m2']}

def sheet(path,title,cells,columns=2,width=1800,cell_h=270):
 margin=26;cw=(width-2*margin)//columns;rows=(len(cells)+columns-1)//columns
 im=Image.new('RGBA',(width,rows*cell_h+100),(0,0,0,0));d=ImageDraw.Draw(im)
 d.rounded_rectangle((margin,15,width-margin,62),radius=8,fill=(236,238,246,235));d.text((margin+12,26),title,font=font,fill='#262C57')
 for i,(label,file) in enumerate(cells):
  x=margin+i%columns*cw;y=84+i//columns*cell_h
  d.text((x+8,y),label,font=small,fill='#70798C',stroke_width=1,stroke_fill='#ECEEF6')
  p=Image.open(file).convert('RGBA');p.thumbnail((cw-16,cell_h-34),Image.Resampling.LANCZOS)
  im.alpha_composite(p,(x+(cw-p.width)//2,y+25+(cell_h-34-p.height)//2))
 im.save(path,optimize=True)
 assert path.stat().st_size<=2*1024*1024,path

def shot(id,material,view):return fixed/f'{id}-{material}-{view}.png'
for fleet,units in roles.items():
 root=run/fleet;dst=root/'selected';dst.mkdir(exist_ok=True);selected=[]
 def add(name,title,cells,**kw):
  p=dst/(name+'.png');sheet(p,title,cells,**kw);selected.append(str(p.relative_to(root)))
 for far in [False,True]:
  suffix='-far' if far else '';lod='FAR' if far else 'NEAR'
  for role in units:
   id=f'klrt-{fleet}-{role}{suffix}'
   add(id,f'{fleet.upper()} | {role.upper()} | {lod} | common metre frame',[(v,shot(id,'color',v)) for v in views])
 for far in [False,True]:
  id=f'klrt-{fleet}-formation'+('-far' if far else '')
  add(id,id+' | exact final-unit assembly',[(v,shot(id,'color',v)) for v in views],cell_h=320)
 for material in ['clay','silhouette']:
  for far in [False,True]:
   suffix='-far' if far else ''
   cells=[(u.upper()+' '+v,shot(f'klrt-{fleet}-{u}{suffix}',material,v)) for u in units for v in views]
   add(material+suffix,f'{fleet.upper()} | {material} | '+('FAR' if far else 'NEAR'),cells,columns=4,width=2200,cell_h=220)
 add('formation-clay-silhouette',fleet.upper()+' | complete formations | clay / silhouette',[(('FAR' if far else 'NEAR')+' '+mat+' '+v,shot(f'klrt-{fleet}-formation'+('-far' if far else ''),mat,v)) for mat in ['clay','silhouette'] for far in [False,True] for v in views],columns=4,width=2200,cell_h=220)
 add('two-fleets-same-metres','CAF 34.166m / Citadis 33.400m | identical metre frames',[(f.upper()+' '+v,shot(f'klrt-{f}-formation','color',v)) for f in roles for v in views],columns=2,cell_h=280)
 comparison=[(id+' '+v,shot(id,'color',v)) for id in ['lrt-five-formation','green-tram-formation',f'klrt-{fleet}-formation'] for v in views]
 if prior:
  id=f'klrt-{fleet}-formation-far'
  comparison += [('same-round '+prior_producer[:8]+' FAR '+v,prior/f'{id}-color-{v}.png') for v in views]
  comparison += [('final FAR '+v,shot(id,'color',v)) for v in views]
 add('existing-style-comparison','OTHER protected models / first delivery / same-round FAR correction',comparison,columns=4,width=2200,cell_h=240)
 add('game-scale','Both fleets at a common small display scale | static studies',[(f.upper()+' '+('FAR' if far else 'NEAR'),shot(f'klrt-{f}-formation'+('-far' if far else ''),'color',v)) for v in ['left','isometric'] for far in [False,True] for f in roles],columns=2,width=1400,cell_h=150)
 assert len(selected)==20
 source=json.loads((repo/'docs/art/kaohsiung-light-rail/sources.json').read_text());source.update(fleet=fleet,producer=producer,previous_producer=None,first_delivery=True,same_round_superseded_producer=prior_producer,same_round_superseded_appearance_acceptance='UNVERIFIED')
 (root/'source-record.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
 status=json.loads((repo/'tools/train-models/status-template.json').read_text())
 status['asset']={'status':'VERIFIED','evidence':'Final producer: '+producer+'. Native readback, shared topology + fault probes, dedicated geometry, independent Swift assembly/Blender importer, PNG decoding, producer rebuild bytes and final delivered browser downloads; see public verification.json and PR for actual evidence/limits.'}
 status['appearance']['evidence']='First delivery. No explicit user acceptance of this producer; maker visual self-review is separate.'
 status['integration']['evidence']='Studies only; shared greenTram/fiveSectionLRT operating mapping, train pack and Red/Orange Siemens untouched. No per-fleet selection contract.'
 status['device']['evidence']='No manual Simulator/Metal/device/FPS/memory/animation/curve validation. Linux WebGL is not a device.'
 (root/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n')
 delivery={'repo':str(repo.resolve()),'producer':producer,'rebuild':'tools/kaohsiung-light-rail/build.sh /absolute/RUN','sources':'source-record.json','status':'status.json','license_files':[],'pngs':selected}
 (root/'delivery.json').write_text(json.dumps(delivery,indent=2)+'\n')
# Public overview: one image for both fleets, all panels from the same native output.
cells=[]
for fleet,length in [('caf','34.166m'),('citadis','33.400m')]:
 role=roles[fleet][0]
 for view in ['front','isometric']:cells.append((fleet.upper()+' | cab | '+view,shot(f'klrt-{fleet}-{role}','color',view)))
 for far in [False,True]:cells.append((fleet.upper()+' | '+length+' | '+('FAR' if far else 'NEAR'),shot(f'klrt-{fleet}-formation'+('-far' if far else ''),'color','isometric')))
sheet(repo/'docs/art/kaohsiung-light-rail/overview.png','Kaohsiung Light Rail | CAF Urbos / Alstom Citadis | first studies',cells,columns=2,width=1800,cell_h=270)
print('20 private PNGs per fleet + 1 shared public overview; native-only, transparent')
