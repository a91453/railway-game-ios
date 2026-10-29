"""Curate revision2 own-work comparison and delivery metadata; no reference photo copies.
python3 curate.py RUN FIXED_COMPARISON CLEAN_PRODUCER_CHECKOUT PRODUCER
"""
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(sys.argv[1]);fixed=Path(sys.argv[2]);repo=Path(sys.argv[3]);producer=sys.argv[4]
source=json.load(open(Path(__file__).resolve().parents[2]/'docs/art/kaohsiung/source-record.json'))
source.update(date='2026-10-29',revision=2,previous_producer='62c2da42bf7edb3ef2e359befe206782fbaaf29b',previous_asset_commit='10f8abc615a84638e121e58b71bbfc1343a20a72',review='Reopened original KRTC/MTBU/Siemens/2427junction images and verified9 downloaded SHA unchanged. Corrected the observer-left destination, bow, windshield/door seams, lamp casting and lower coupler. No third-party original images redistributed.')
(root/'source-record.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
status={'asset':{'status':'VERIFIED','evidence':'Final native/GLB geometry and actual faults, protectedT/hardware and688 existing payloads, independent producer rebuild, Blender4.3.2, PNG decode and delivered viewer/download SHA. See public verification.json.'},'appearance':{'status':'UNVERIFIED','accepted_producer':None,'evidence':'Producer visual self-review only. User authorized further corrections, not appearance acceptance of this revision.'},'integration':{'status':'UNVERIFIED','evidence':'studies only; krtc metroGeneric3-car mapping protected.'},'device':{'status':'UNVERIFIED','evidence':'Linux WebGL/Blender, no new Simulator/device Metal/performance/animation check. file:// blocked by browser policy, localhost tested.'}}
(root/'status.json').write_text(json.dumps(status,indent=2)+'\n')
# Native images from identical fixed camera/metre/light frames, not independently fitted.
im=Image.new('RGBA',(1280,820),(0,0,0,0));d=ImageDraw.Draw(im)
for col,tag in enumerate(['before','after']):
 d.text((col*640+15,12),tag+' / '+('62c2da42' if tag=='before' else producer[:8]),fill=(38,44,87,255))
 q=Image.open(fixed/f'kaohsiung-dm1-color-front-{tag}.png');im.alpha_composite(q,(col*640,36))
 q=Image.open(fixed/f'kaohsiung-dm1-color-isometric-{tag}.png');q=q.resize((640,256));im.alpha_composite(q,(col*640,540))
(root/'png/day/before-after-fixed.png').parent.mkdir(parents=True,exist_ok=True);im.save(root/'png/day/before-after-fixed.png',optimize=True)
pngs=['png/day/kaohsiung-dm1-'+v+'.png' for v in ['front','back','left','right','top','bottom','isometric']]
pngs+=['png/day/'+i+'-isometric.png' for i in ['kaohsiung-t','kaohsiung-dm2','kaohsiung-dm1-far','kaohsiung-t-far','kaohsiung-dm2-far','kaohsiung-formation','kaohsiung-formation-far']]
pngs+=['png/day/kaohsiung-formation-'+v+'.png' for v in ['left','top']]
pngs+=['png/day-clay/kaohsiung-dm1-front.png','png/day/before-after-fixed.png','png/day-silhouette/kaohsiung-dm1-front.png','png/night/kaohsiung-formation-isometric.png']
assert len(pngs)==20
spec={'repo':str(repo.resolve()),'producer':producer,'previous_producer':'62c2da42bf7edb3ef2e359befe206782fbaaf29b','rebuild':'tools/train-models/run.sh OUT --ids kaohsiung-dm1,kaohsiung-t,kaohsiung-dm2,kaohsiung-dm1-far,kaohsiung-t-far,kaohsiung-dm2-far --assembly-spec tools/kaohsiung/assembly.json; node tools/train-models/package.mjs OUT','sources':'source-record.json','status':'status.json','license_files':[],'pngs':pngs}
(root/'delivery.json').write_text(json.dumps(spec,indent=2)+'\n')
