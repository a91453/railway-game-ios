"""Freeze real producer provenance; extract ZIP fully and compare every byte."""
import hashlib,json,subprocess,sys,tempfile,zipfile
from pathlib import Path
root=Path(sys.argv[1]).resolve();commit=sys.argv[2];repo=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert subprocess.check_output(['git','rev-parse',commit],cwd=repo,text=True).strip()==commit
paths=['Sources/GamePresentation/Map3DC341.swift','Sources/GamePresentation/Map3DModels.swift']+[str(p.relative_to(repo)) for p in (repo/'tools/c341').iterdir() if p.is_file()]+['tools/station-kit/package.mjs','tools/station-kit/renderer.js']
for p in paths:assert subprocess.check_output(['git','show',commit+':'+p],cwd=repo)==(repo/p).read_bytes(),p
record={'producer_repository':'a91453/railway-game-ios','producer_commit':commit,'producer_files':{p:sha(repo/p) for p in paths},'references':'four inline owner images viewed individually; Blair Yu 341 photo opened locally; see reference-review.json','dimensions':'all model dimensions are proportional estimates; no verified C341 engineering dimensional source','prior':'genuine first export producer 78890070 kept in sibling revision-1 with actual native/GLB/previews/recipe; never reconstructed after the fact','comparison':'EMU3000 for palette, matte style and detail density only; no geometry reused','coordinates':'metres +X front +Y left +Z up; glTF x,z,-y'}
(root/'source-record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
exclude={'asset-package.zip','package-verification.json','SHA256SUMS.txt'}
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in exclude)
(root/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(root).as_posix()}\n' for p in files));files.append(root/'SHA256SUMS.txt')
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in files:z.write(p,p.relative_to(root).as_posix())
with tempfile.TemporaryDirectory() as temp:
 with zipfile.ZipFile(root/'asset-package.zip') as z:
  assert z.testzip() is None;z.extractall(temp);assert set(z.namelist())=={str(p.relative_to(root)) for p in files}
 for p in files:assert (Path(temp)/p.relative_to(root)).read_bytes()==p.read_bytes()
(root/'package-verification.json').write_text(json.dumps({'status':'VERIFIED','producer_commit':commit,'files':len(files),'zip_sha256':sha(root/'asset-package.zip'),'checks':['CRC','full extraction','file set equality','every extracted file compared byte-for-byte']},indent=2)+'\n')
print('VERIFIED extracted ZIP, producer source bytes, and SHA records')
