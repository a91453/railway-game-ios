"""Pin real committed producer source; verify live files and complete ZIP extraction."""
import hashlib,json,subprocess,sys,zipfile,tempfile
from pathlib import Path
root=Path(sys.argv[1]).resolve();producer=sys.argv[2]
sha=lambda b:hashlib.sha256(b).hexdigest()
assert subprocess.check_output(['git','rev-parse',producer],text=True).strip()==producer
paths=['Sources/GamePresentation/Map3DEMU900.swift','Sources/GamePresentation/Map3DModels.swift','Sources/GamePresentation/Map3DTrainSets.swift','Sources/GamePresentation/Map3DGeometry.swift','Sources/GamePresentation/Map3DProps.swift','Sources/GamePresentation/Map3DStationKitGeometry.swift','Sources/GamePresentation/Map3DE500.swift','Sources/GamePresentation/Map3DEMU3000.swift','Tests/GamePresentationTests/Map3DEMU900Tests.swift','tools/station-kit/package.mjs','tools/station-kit/renderer.js']
paths+=['Tests/GamePresentationTests/Map3DModelTests.swift','Sources/GamePresentation/TrainLivery.swift','Sources/GamePresentation/Map3DCivicKitGeometry.swift']
paths+=sorted(str(p) for p in Path('tools/emu900-native').glob('*') if p.is_file())
paths+=sorted(str(p) for p in Path('docs/art/emu900-native-2026-10-27').glob('*') if p.is_file())
records=[]
for path in sorted(set(paths)):
 b=subprocess.check_output(['git','show',producer+':'+path]);assert b==Path(path).read_bytes(),path
 target=root/'producer-source'/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b)
 records.append({'path':path,'sha256':sha(b)})
m=json.loads((root/'manifest.json').read_text());assert m['producer_commit']==producer
assert (root/'previews/overview.png').read_bytes()==Path('docs/art/emu900-native-2026-10-27/overview.png').read_bytes(),'public overview differs from final native render'
for model in m['models']:
 for kind in ['native','glb']:assert sha((root/model[kind]).read_bytes())==model[kind+'_sha256']
 for direction,metric in model['view_metrics'].items():assert sha((root/model['views'][direction]).read_bytes())==metric['sha256']
(root/'source.json').write_text(json.dumps({'producer_commit':producer,'base_commit':'e89929efbf7f6d19f9d3f453beb5e378d9fb2331','accepted_emu3000_producer':'66a515e8f84ddb5001bae2dd0ce5d79f49063113','accepted_e500_producer':'85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a','files':records,'limits':'E500 comparison uses its own accepted source producer. Before comparison is the actual prior commuter display (EMU800), not a previous independent EMU900. Source records describe code inputs, not engineering measurement accuracy.'},indent=2)+'\n')
excluded={'asset-package.zip','package-verification.json','SHA256SUMS'}
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in excluded)
(root/'SHA256SUMS').write_text(''.join(sha(p.read_bytes())+'  '+str(p.relative_to(root))+'\n' for p in files))
files.append(root/'SHA256SUMS');files.sort()
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in files:z.write(p,p.relative_to(root))
with tempfile.TemporaryDirectory() as t,zipfile.ZipFile(root/'asset-package.zip') as z:
 assert z.testzip() is None;z.extractall(t)
 assert set(z.namelist())==set(str(p.relative_to(root)) for p in files)
 for p in files:assert (Path(t)/p.relative_to(root)).read_bytes()==p.read_bytes()
(root/'package-verification.json').write_text(json.dumps({'status':'VERIFIED','producer_commit':producer,'members':len(files),'zip_sha256':sha((root/'asset-package.zip').read_bytes()),'checks':['CRC','complete extraction','exact member set','every extracted byte matches','committed producer sources match','public overview bytes equal final render']},indent=2)+'\n')
print('VERIFIED ZIP extraction and',len(files),'file payloads')
