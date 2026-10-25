"""Pin real committed producer source, verify all bytes, and create/extract complete ZIP."""
import hashlib,json,subprocess,sys,zipfile,tempfile
from pathlib import Path
root=Path(sys.argv[1]).resolve();producer=sys.argv[2]
sha=lambda b:hashlib.sha256(b).hexdigest()
assert subprocess.check_output(['git','rev-parse',producer],text=True).strip()==producer
paths=['Sources/GamePresentation/Map3DE500.swift','Sources/GamePresentation/Map3DTrainSets.swift','Tests/GamePresentationTests/Map3DE500Tests.swift','Tests/GamePresentationTests/Map3DTrainSetTests.swift','docs/art/e500-refresh-2026-10-25/README.md','docs/art/e500-refresh-2026-10-25/reference-record.json']
paths+=sorted(str(p) for p in Path('tools/e500-refresh').glob('*') if p.is_file())
records=[]
for path in paths:
 b=subprocess.check_output(['git','show',producer+':'+path]);assert b==Path(path).read_bytes(),path
 target=root/'producer-source'/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b)
 records.append({'path':path,'sha256':sha(b)})
m=json.loads((root/'manifest.json').read_text());assert m['producer_commit']==producer
assert (root/'previews/overview.png').read_bytes()==Path('docs/art/e500-refresh-2026-10-25/overview.png').read_bytes(),'public overview differs from final render'
for model in m['models']:
 for kind in ['native','glb']:assert sha((root/model[kind]).read_bytes())==model[kind+'_sha256']
(root/'source.json').write_text(json.dumps({'producer_commit':producer,'baseline_commit':'41c00fa51f7975d1423b1645aadb9d5b019ff6a1','previous_producer':'8127c765f8c07570de17b813b6329b93d9871a68','files':records},indent=2)+'\n')
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in ['asset-package.zip','package-verification.json'])
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in files:z.write(p,p.relative_to(root))
with tempfile.TemporaryDirectory() as t, zipfile.ZipFile(root/'asset-package.zip') as z:
 assert z.testzip() is None;z.extractall(t)
 assert set(z.namelist())==set(str(p.relative_to(root)) for p in files)
 for p in files:assert (Path(t)/p.relative_to(root)).read_bytes()==p.read_bytes()
(root/'package-verification.json').write_text(json.dumps({'status':'VERIFIED','producer_commit':producer,'members':len(files),'zip_sha256':sha((root/'asset-package.zip').read_bytes()),'checks':['CRC','complete extraction','exact member set','every extracted byte matches','committed producer sources match']},indent=2)+'\n')
print('VERIFIED ZIP extraction and',len(files),'file payloads')
