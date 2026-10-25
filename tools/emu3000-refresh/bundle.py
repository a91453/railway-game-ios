"""Pin the actual producer, verify source bytes and final package, extract every member."""
import sys,json,hashlib,subprocess,zipfile,tempfile
from pathlib import Path
root=Path(sys.argv[1]).resolve();producer=sys.argv[2];repo=Path(__file__).resolve().parents[2]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((root/'manifest.json').read_text());assert manifest['producer_commit']==producer,'Re-export with PRODUCER_COMMIT; do not patch provenance after export'
source_files=sorted((repo/'Sources/GamePresentation').glob('*.swift'))+sorted(p for p in (repo/'tools/emu3000-refresh').iterdir() if p.is_file())+[repo/'tools/station-kit/package.mjs',repo/'tools/station-kit/renderer.js',repo/'Tests/GamePresentationTests/Map3DEMU3000Tests.swift',repo/'Tests/GamePresentationTests/Map3DTrainSetTests.swift']
for p in source_files:
 assert subprocess.check_output(['git','show',f'{producer}:{p.relative_to(repo)}'],cwd=repo)==p.read_bytes(),('Producer source differs',p)
for m in manifest['models']:
 for kind in ['native','glb']:
  assert sha(root/m[kind])==m[kind+'_sha256'],('model changed after export',m['id'],kind)
 for v,metrics in m['view_metrics'].items():assert sha(root/m['views'][v])==metrics['sha256'],('view differs',m['id'],v)
# No raw reference image/mesh/texture is copied to the deliverable.
refs=json.loads((root/'reference-review.json').read_text())
source_record={'producer_repository':'a91453/railway-game-ios','producer_commit':producer,'private_base':'81e935fd','baseline_producer':'85d9aa359dfcd6213f76a6559abebd9155806e97','source_files_sha256':{str(p.relative_to(repo)):sha(p) for p in source_files},'reference_review':'reference-review.json','references':refs,'accepted_style_comparisons':{'producer':'04b051b059004baea5744c444c48fdd06e3d8349','ids':['refresh-700t-cab','refresh-e200'],'use':'palette, matte material and detail density only; body/nose/doors/bogies/formation not copied'},'runtime':'Dedicated EMU3000 8 roles, near below500m and far to900m; actual frame test; no GameCore/save/fixture/gameplay edits','previous_delivery':{'producer_commit':'e25474fffe42a98fd6cbc04b5f287485be72e097','private_commit':'aef61a8773d39572acb0d5e0ca4a76be940b0311','complete_archive':'Railway/game-art-previews/docs/art/emu3000-refresh-2026-10-25/revision-3','native_snapshot':'history/e25474ff'},'first_pass':'history/first-pass preserves genuine uncommitted production snapshot, not an accepted or Git-pinned release','limits':['all unseen-side fittings/nose/underframe positions are proportion estimates','primary original operating-manual PDF not obtained','static geometry; doors/wheels/pantographs do not animate','Linux WebGL is not Metal/device/performance/animation verification','full contact/collision graph and real overhead contact not verified']}
previous=root/'history/e25474ff'
if previous.exists():
 old=json.loads((previous/'manifest.json').read_text())
 assert old['producer_commit']=='e25474fffe42a98fd6cbc04b5f287485be72e097'
 for m in old['models']:
  if m['family'] in ['emu3000','far']:
   assert sha(previous/m['native'])==m['native_sha256'],('previous delivery modified',m['id'])
interim=root/'history/f6a010f0'
if interim.exists():
 study=json.loads((interim/'manifest.json').read_text());assert study['producer_commit']=='f6a010f05beac8a41d5c40dca25ab9a054478b90'
 for m in study['models']:
  if m['family'] in ['emu3000','far']:assert sha(interim/m['native'])==m['native_sha256']
 source_record['intermediate_study']={'producer_commit':study['producer_commit'],'native_snapshot':'history/f6a010f0','status':'actual small-chin interim study; not a complete delivery or owner-approved version'}
(root/'source-record.json').write_text(json.dumps(source_record,ensure_ascii=False,indent=2)+'\n')
# The sole public overview must be from these exact final native assets.
public=repo/'docs/art/emu3000-refresh-2026-10-25/overview.png'
assert public.read_bytes()==(root/'previews/overview.png').read_bytes(),'public overview differs from final export'
exclude={'asset-package.zip','SHA256SUMS.txt','package-verification.json'}
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in exclude)
(root/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+str(p.relative_to(root))+'\n' for p in files));files.append(root/'SHA256SUMS.txt')
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in files:z.write(p,p.relative_to(root))
with zipfile.ZipFile(root/'asset-package.zip') as z,tempfile.TemporaryDirectory() as tmp:
 assert z.testzip() is None;z.extractall(tmp)
 assert set(z.namelist())=={str(p.relative_to(root)) for p in files}
 for p in files:assert (Path(tmp)/p.relative_to(root)).read_bytes()==p.read_bytes(),p
result={'status':'VERIFIED','producer_commit':producer,'file_count':len(files),'zip_sha256':sha(root/'asset-package.zip'),'checks':['source bytes equal actual producer commit','native/GLB and all seven-way PNG hashes','public overview equals private final native render','ZIP CRC','full extraction','exact member set','every byte equal'],'limits':'package-verification.json is external to the ZIP to avoid a self-referential archive hash'}
(root/'package-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('VERIFIED ZIP full extraction and byte comparison:',len(files),'files')
