"""Verify actual producer bytes, archive, extract, compare all members."""
from pathlib import Path
import sys,json,subprocess,hashlib,zipfile,tempfile
root=Path(sys.argv[1]).resolve(); commit=sys.argv[2]; repo=Path(__file__).resolve().parents[2]
files=[repo/'Sources/GamePresentation/Map3DTrainShapeRefresh.swift',repo/'Sources/GamePresentation/Map3DModels.swift',repo/'tools/station-kit/package.mjs',repo/'tools/station-kit/renderer.js']+list((repo/'tools/train-shape-refresh').glob('*'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for p in files:
 if p.is_file(): assert subprocess.check_output(['git','show',f'{commit}:{p.relative_to(repo)}'],cwd=repo)==p.read_bytes(),p
record={'producer_commit':commit,'producer_repository':'a91453/railway-game-ios','private_source_base':'3bc65fc25bdc882d9bda730c2be7a00cab22cf7a','files_sha256':{str(p.relative_to(repo)):sha(p) for p in files if p.is_file()},'sources':['user-provided 700T side photograph in conversation 2026-10-24 (viewed; not redistributed)','https://blair-train.blogspot.com/2010/02/e200.html','https://blair-train.blogspot.com/2010/02/700t.html','https://github.com/a91453/railway-game-ios/pull/1203','private Simulator/reference_snapshot/models/tra-e201/tra-e201.glb (visual study only)'],'reference_policy_update':'Codex models may be reused; non-Codex source models are visual references only. Prior Codex recipe 05248513 is this paint-only revision base; no E201 source vertices/textures copied.','reference_policy':'photos viewed locally only; no photos, logos, source meshes or textures distributed','limitations':['static study, no operational replacement','proportional estimates except sourced E200 body length/width','device Metal, performance, animation unverified'],'initial_history':'actual delivered producer 05248513 models/manifest/source/recipe retained in history/05248513; prior complete revision-4 remains in the private repo'}
(root/'source-record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
m=json.loads((root/'manifest.json').read_text());m['producer_commit']=commit;(root/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
excluded={'asset-package.zip','SHA256SUMS.txt','package-verification.json'}
fs=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in excluded)
(root/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+str(p.relative_to(root))+'\n' for p in fs));fs.append(root/'SHA256SUMS.txt')
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in fs:z.write(p,p.relative_to(root))
with zipfile.ZipFile(root/'asset-package.zip') as z,tempfile.TemporaryDirectory() as td:
 assert z.testzip() is None;z.extractall(td)
 assert set(z.namelist())=={str(p.relative_to(root)) for p in fs}
 for p in fs:assert (Path(td)/p.relative_to(root)).read_bytes()==p.read_bytes()
(root/'package-verification.json').write_text(json.dumps({'status':'VERIFIED','producer_commit':commit,'files':len(fs),'zip_sha256':sha(root/'asset-package.zip'),'checks':['full extraction','CRC','file set','byte equality']},indent=2)+'\n')
print('VERIFIED ZIP',len(fs),'files')
