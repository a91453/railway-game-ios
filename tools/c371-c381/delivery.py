"""Publish each train's latest study using railway-assets-private's 2026-10-28 rules.

The full temporary export is independently checked first. Only 19 PNGs per train
are copied: seven day, seven night, four other-unit isometrics, true comparison.
Older complete deliveries remain reachable at their recorded git commits.
"""
from pathlib import Path
import copy, hashlib, json, shutil, subprocess, sys
from PIL import Image
source,prior,destination=map(Path,sys.argv[1:4])
producer=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base=json.loads((source/'manifest.json').read_text())
recipe_paths=['Sources/GamePresentation/'+n for n in ['Map3DC371.swift','Map3DC381.swift','Map3DMetroStudyGeometry.swift','Map3DModels.swift','Map3DTrainMaterial.swift']]+['Tests/GamePresentationTests/Map3DC371C381Tests.swift','tools/train-models/hashes.lock.json']+[str(p) for p in Path('tools/c371-c381').iterdir() if p.is_file()]
recipe_hashes={p:sha(Path(p)) for p in recipe_paths}
for train in ['c371','c381']:
 root=destination/(train+'-2026-10-28')/'revision-1'
 if root.exists():shutil.rmtree(root)
 root.mkdir(parents=True)
 def put(src,relative):
  target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target);return relative
 manifest=copy.deepcopy(base);manifest['models']=[m for m in manifest['models'] if m['id'].startswith(train+'-')];assert len(manifest['models'])==5
 for m in manifest['models']:
  for key in ['native','glb']:put(source/m[key],m[key])
  if m.get('assembly_expected'):put(source/m['assembly_expected'],m['assembly_expected'])
  directions=manifest['directions'] if m['id']==train+'-dm' else ['isometric']
  m['views']={v:put(source/'game-light/png/day'/(m['id']+'-'+v+'.png'),'views/'+m['id']+'/'+v+'.png') if m['category']!='formation' else put(source/'views'/m['id']/(v+'.png'),'views/'+m['id']+'/'+v+'.png') for v in directions}
  m.pop('view_metrics',None)
 for v in manifest['directions']:put(source/'game-light/png/night'/(train+'-dm-'+v+'.png'),'previews/night/'+v+'.png')
 put(source/'comparison'/(train+'-before-after.png'),'previews/before-after.png')
 for name in ['renderer.js','index.html']:put(source/name,name)
 manifest.update({'model_count':5,'producer_commit':producer,'published_preview_count':19,'render_verification':{'status':'VERIFIED','interactive_directions_per_model':7,'published_png_count':19,'limits':'All unit PNGs use the shared game-light renderer; formation isometric and matched comparison use bare native renderer. All temporary clay/silhouette/seven-view exports were reviewed but are not duplicated here.'}})
 manifest['assembly']={k:v for k,v in manifest['assembly'].items() if not k.startswith(('c371_','c381_')) or k.startswith(train+'_')}
 (root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 for name in ['geometry-verification.json','assembly-verification.json','glb-import-verification.json','front-visibility-verification.json','underframe-contact-verification.json','c381-revision-verification.json','producer-rebuild-verification.json','common-payload-verification.json','verification-summary.json']:
  put(source/name,'verification/'+name)
 model_files=[p for p in (root/'models').iterdir() if p.is_file()];assert len(model_files)==10
 record={'producer_repository':'a91453/railway-game-ios','producer_commit':producer,'producer_files_sha256':recipe_hashes,'main_rules_reviewed':'8be2242361f3622eeb0853bd3bd01db05631354f','assets_rules_base':'c77954d9165d5d2306fcffd723239ed871ab376d','rebuild':'tools/c371-c381/export.sh OUT; shared train-models export/render; delivery.py OUT TRUE_PRIOR DELIVERY_ROOT; standalone.mjs DELIVERED_ROUND','source':'own Swift recipe; photo observation only; see public C381_REFERENCE_RECHECK.md and REFERENCE_RECHECK.md','license':'Own work in the existing project. No third-party photographs, textures or meshes redistributed.','previous_complete_version':{'repository':'a91453/railway-reference-private','commit':'63b446933a7ed0e31b2a565b0bb46f09f69fa54b','artifact_commit':'e791fdb7b34caf522b469550cb1f1a066b1d4515','path':'Railway/game-art-previews/docs/art/c371-c381-2026-10-27','producer':'cf8d79ba59f3965961d8cca7e67673fbae920472','models_sha256':{p.name:sha(p) for p in (prior/'models').glob(train+'-*')}},'appearance':'PENDING USER ACCEPTANCE. Earlier inferred C371 acceptance withdrawn after the user expressed uncertainty. Technical checks are separate.','models_sha256':{p.name:sha(p) for p in model_files},'published_png':19,'temporary_previews':'77 dedicated +112 shared day/night were validated locally, including unpublished clay/silhouette; not all are committed because of the preview cap.','format':'M3DM v1, <=15000 triangles per independently loadable unit; M3DAssembly embeds only its four referenced final unit types. GLB axes +X front,+Y up,-Z left; native +X front,+Y left,+Z up, metres,railZ0.','game_integration':'Map3DModelPack.studies only. No new operating mapping; standard remains529 models/3127704 vertices. No merge/auto-merge/TestFlight.','unverified':['user appearance acceptance','Simulator appearance this round','real-device Metal','performance','animation','exhaustive collisions/engineering','hidden equipment positions','direct file protocol launch'],'exact_head_ci':'Query public PR1342; older results do not establish current head.'}
 (root/'source-record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
 (root/'SOURCE.md').write_text('# Source and rights\n\nOrigin: own Swift recipes in a91453/railway-game-ios; photographs observed, no pixels/meshes redistributed.\nDate: 2026-10-28.\nLicense: own project work; no third-party binaries.\nLicense file: no additional third-party license applies to these generated models.\nPublic use: source code and one overview only; this complete study delivery remains private.\nReference URLs, authors, licenses and SHA: public docs/art/c371-c381-2026-10-27/C381_REFERENCE_RECHECK.md and REFERENCE_RECHECK.md.\n')
 (root/'README.md').write_text(f'''# {train.upper()} — 2026-10-28 revision-1 in the new assets repository

Producer: `{producer}` in `a91453/railway-game-ios` (Agent: Codex).
Appearance: **pending user acceptance**. A completed export is not appearance approval.

Rebuild from this producer with Swift6.4:

```sh
tools/c371-c381/export.sh OUT
tools/train-models/run.sh OUT/game-light --tag after --ids c371-dm,c371-t,c371-m,c371-rear,c381-dm,c381-t,c381-m,c381-rear
CHROMIUM_PATH=/usr/bin/chromium node tools/train-models/render.mjs OUT/game-light --time both
node tools/c371-c381/render.mjs OUT
node tools/c371-c381/clay.mjs OUT
node tools/c371-c381/revision-compare.mjs TRUE_PRIOR OUT
# Run native audits, independent Blender import and producer rebuild; see public handoff.
python3 tools/c371-c381/delivery.py OUT TRUE_PRIOR DELIVERY_ROOT
node tools/c371-c381/standalone.mjs DELIVERY_ROOT/{train}-2026-10-28/revision-1
```

Source/rights: `SOURCE.md`; original-photo URLs/SHA/licenses and assumptions are in the public reference notes. No photographs are redistributed. Native units and GLBs are own geometry, metres, native +Xfront/+Yleft/+Zup. The six-car display is M3DAssembly, not an oversized M3DM. Only four referenced final unit types are embedded.

Genuine full previous delivery: `a91453/railway-reference-private` commit `63b446933a7ed0e31b2a565b0bb46f09f69fa54b`, artifact commit `e791fdb7b34caf522b469550cb1f1a066b1d4515`, path `Railway/game-art-previews/docs/art/c371-c381-2026-10-27`; producer `cf8d79ba59f3965961d8cca7e67673fbae920472`. Its exact files and ZIP remain available in git. Do not read the old repository's main, where migrated art was deleted. This new delivery does not duplicate history or ZIP.

19 published PNGs: seven DM day +seven DM night +T/M/rear/formation isometrics +genuine matched-camera comparison. More clay/silhouette and all-unit views were checked locally. One final candidate; no sequence/video. Only this latest revision holds models and viewer. `index.html` serves local files; `viewer-standalone.html` embeds downloads and does not fetch external resources. Direct file-protocol launch is not established by loopback tests.

Static study only, in Map3DModelPack.studies; standard runtime pack stays529 models/3127704 vertices. No operating mapping or gameplay change. Device Metal, animation, performance, exhaustive collisions and hidden equipment remain unverified. Draft only; no merge or TestFlight.
''')
 (root.parent/'README.md').write_text(f'# {train.upper()} study\n\nCurrent round: [revision-1](revision-1/README.md). Only the latest round holds heavy files. Full genuine previous delivery remains at the immutable git commits recorded in revision-1/source-record.json. Appearance pending user acceptance.\n')
 shutil.copy2(root/'SOURCE.md',root.parent/'SOURCE.md')
 png=list(root.rglob('*.png'));assert len(png)==19
 for p in png:
  Image.open(p).load();assert p.stat().st_size<=2*1024**2
 files=list(p for p in root.rglob('*') if p.is_file());assert all(p.stat().st_size<=50*1024**2 for p in files)
 assert all(not set(p.relative_to(root).parts)&{'history','old','backup'} and p.suffix.lower()!='.zip' for p in files)
 print(train,len(model_files),'model files',len(png),'published PNGs',sum(p.stat().st_size for p in files),'bytes')
