import json,hashlib,sys,subprocess,zipfile,tempfile
from pathlib import Path
root=Path(sys.argv[1]);producer=sys.argv[2]
assert subprocess.check_output(['git','rev-parse',producer],text=True).strip()==producer
paths=['Sources/GamePresentation/Map3DTaipei610.swift','Sources/GamePresentation/Map3DModels.swift','Sources/GamePresentation/Map3DStationKitGeometry.swift','Sources/GamePresentation/Map3DGeometry.swift','Sources/GamePresentation/Map3DProps.swift','Sources/GamePresentation/Map3DScene.swift','Tests/GamePresentationTests/Map3DTaipei610Tests.swift']
for folder in ['tools/train-models','tools/taipei610-audit']:
 paths+=subprocess.check_output(['git','ls-tree','-r','--name-only',producer,'--',folder],text=True).splitlines()
records=[]
for p in paths:
 b=subprocess.check_output(['git','show',producer+':'+p]);assert b==Path(p).read_bytes(),p
 target=root/'producer-source'/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b);records.append({'path':p,'sha256':hashlib.sha256(b).hexdigest()})
(root/'producer.json').write_text(json.dumps({'producer_commit':producer,'source_files':records,'rebuild':'clone public producer; read tools/taipei610-audit/README.md; fixed accepted comparisons come from private main captured at ba1ac3e5','not_engineering_precision':True},indent=2))
exclude={'asset-package.zip','package-verification.json','remote-download-verification.json','SHA256SUMS'}
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in exclude)
(root/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n' for p in files));files.append(root/'SHA256SUMS')
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in files:z.write(p,p.relative_to(root))
with tempfile.TemporaryDirectory() as d,zipfile.ZipFile(root/'asset-package.zip') as z:
 assert z.testzip() is None;z.extractall(d);assert set(z.namelist())=={str(p.relative_to(root)) for p in files}
 for p in files:assert (Path(d)/p.relative_to(root)).read_bytes()==p.read_bytes()
(root/'package-verification.json').write_text(json.dumps({'status':'VERIFIED','producer_commit':producer,'members':len(files),'sha256':hashlib.sha256((root/'asset-package.zip').read_bytes()).hexdigest(),'checks':['CRC','complete extraction','member set','all bytes','committed source bytes']},indent=2))
print('VERIFIED ZIP',len(files))
