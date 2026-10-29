"""Curate revision3 own-work comparison and delivery metadata; no reference photo copies.
python3 curate.py RUN FIXED_COMPARISON CLEAN_PRODUCER_CHECKOUT PRODUCER
"""
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(sys.argv[1]);fixed=Path(sys.argv[2]);repo=Path(sys.argv[3]);producer=sys.argv[4]
source=json.load(open(Path(__file__).resolve().parents[2]/'docs/art/kaohsiung/source-record.json'))
source.update(date='2026-10-29',revision=3,previous_producer='3874b4259a99bd7b4f7e42f1b94fa23a34d4cf2c',previous_asset_commit='1f73fb1cdba56ce99e0e3cdc3313175915d0ac92',review='Reopened original KRTC/MTBU/Siemens/2427junction images and verified9 downloaded SHA unchanged. Front paint partitions only: more finely sampled U band and arched crown/black-mask border with eased outer shoulders. Same physical bow; accepted straight side and complete T payload protected against revision2. No third-party original images redistributed.')
(root/'source-record.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
status={'asset':{'status':'VERIFIED','evidence':'Final native/GLB geometry and actual faults, protected accepted side / T / bow and696 existing payloads, independent producer rebuild, Blender4.3.2, PNG decode and delivered viewer/download SHA. See public verification.json.'},'appearance':{'status':'UNVERIFIED','accepted_producer':None,'accepted_sections':[{'section':'side','producer':'3874b4259a99bd7b4f7e42f1b94fa23a34d4cf2c','evidence':'User: 側面可以了 只是正面塗裝是不是有點方 還要調整嗎'}],'evidence':'Revision2 side accepted only. Revision3 front remains producer self-review; no whole-model appearance acceptance.'},'integration':{'status':'UNVERIFIED','evidence':'studies only; krtc metroGeneric3-car mapping protected.'},'device':{'status':'UNVERIFIED','evidence':'Linux WebGL/Blender, no new Simulator/device Metal/performance/animation check. file:// blocked by browser policy, localhost tested.'}}
(root/'status.json').write_text(json.dumps(status,indent=2)+'\n')
# Native images from identical fixed camera/metre/light frames, not independently fitted.
im=Image.new('RGBA',(1280,820),(0,0,0,0));d=ImageDraw.Draw(im)
for col,tag in enumerate(['before','after']):
 d.text((col*640+15,12),tag+' / '+('3874b425' if tag=='before' else producer[:8]),fill=(38,44,87,255))
 q=Image.open(fixed/f'kaohsiung-dm1-color-front-{tag}.png');im.alpha_composite(q,(col*640,36))
 q=Image.open(fixed/f'kaohsiung-dm1-color-isometric-{tag}.png');q=q.resize((640,256));im.alpha_composite(q,(col*640,540))
(root/'png/day/before-after-fixed.png').parent.mkdir(parents=True,exist_ok=True);im.save(root/'png/day/before-after-fixed.png',optimize=True)
pngs=['png/day/kaohsiung-dm1-'+v+'.png' for v in ['front','back','left','right','top','bottom','isometric']]
pngs+=['png/day/'+i+'-isometric.png' for i in ['kaohsiung-t','kaohsiung-dm2','kaohsiung-dm1-far','kaohsiung-t-far','kaohsiung-dm2-far','kaohsiung-formation','kaohsiung-formation-far']]
pngs+=['png/day/kaohsiung-formation-'+v+'.png' for v in ['left','top']]
pngs+=['png/day-clay/kaohsiung-dm1-front.png','png/day/before-after-fixed.png','png/day-silhouette/kaohsiung-dm1-front.png','png/night/kaohsiung-formation-isometric.png']
assert len(pngs)==20
spec={'repo':str(repo.resolve()),'producer':producer,'previous_producer':'3874b4259a99bd7b4f7e42f1b94fa23a34d4cf2c','rebuild':'tools/train-models/run.sh OUT --ids kaohsiung-dm1,kaohsiung-t,kaohsiung-dm2,kaohsiung-dm1-far,kaohsiung-t-far,kaohsiung-dm2-far --assembly-spec tools/kaohsiung/assembly.json; node tools/train-models/package.mjs OUT','sources':'source-record.json','status':'status.json','license_files':[],'pngs':pngs}
(root/'delivery.json').write_text(json.dumps(spec,indent=2)+'\n')
