"""Record the actual Git producer, ZIP, fully extract and byte-compare every file."""
import hashlib,json,subprocess,sys,tempfile,zipfile
from pathlib import Path
root=Path(sys.argv[1]).resolve();commit=sys.argv[2];source=Path(__file__).resolve().parents[2]
assert len(commit)==40 and all(c in '0123456789abcdef' for c in commit)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
producer_files=sorted(set(list((source/'Sources/GamePresentation').glob('Map3D*.swift'))+[source/'tools/station-kit/package.mjs',source/'tools/station-kit/renderer.js']+[p for p in (source/'tools/steam-tender').glob('*') if p.is_file()]))
for p in producer_files:
    rel=p.relative_to(source).as_posix()
    assert subprocess.check_output(['git','show',f'{commit}:{rel}'],cwd=source)==p.read_bytes(),f'Stale producer: {rel}'
refs=sorted((root/'references').glob('*.jpg'));assert len(refs)==10
record={'producer_repository':'a91453/railway-game-ios','producer_commit':commit,
 'recipes':['Sources/GamePresentation/Map3DSteamTender.swift'],
 'producer_files_sha256':{p.relative_to(source).as_posix():sha(p) for p in producer_files},
 'references':{p.relative_to(root).as_posix():sha(p) for p in refs},
 'reference_review':'all ten owner images individually opened; reference-review.md maps observations per image',
 'private_base_commit':'87a94c7888fe8bdb5d45bfdddf266af4caa0ff1e',
 'private_lookup':['Taiwan garage-blender-v1 README and ct273.json: Q-proportions, engineeringDimensionsM=null; not evidence for this model identity or engineering dimensions; no mesh imported','World rolling-stock catalog README and catalog-2026-10.json: urban passenger stock, no unique match','OpenWorld train-model-specs.js: futuristic maglev/HSR/TRA, no unique steam match'],
 'reuse':'project palette, low-level closed solids and export/viewer tooling only; no previous vehicle body/chassis/cab/window/formation recipe reused',
 'history':'history/initial and history/support-revision preserve real prototypes; history/front-before preserves public producer843e6db8 before the owner front-wheel feedback correction',
 'front_wheel_revision':{'prior_producer_commit':'843e6db89a015a57eb64748764725596dd28d3b9','scope':'32 added front running-gear solids; every original locomotive solid and tender unchanged','evidence':'front-revision-verification.json, front-defect-verification.json, previews/steam-front-side-by-side.png'},
 'native_axes':'metres, +x front, +y left, +z up; rail z=0',
 'assembly':{'units':['steam-locomotive','steam-tender'],'translations_m':[[4.35,0,0],[-7.25,0,0]],'rotations_rad':[0,0],'body_gap_m':0.60},
 'style':'existing matte teal / graphite / sand palette; no red, brands, photographic textures',
 'limitations':['static asset only; merging does not replace operating trains','all metre specifications are proportional display estimates','concealed exact axle designation / real type unknown','device Metal / performance / animation / moving clearances / mechanical strength unverified']}
manifest_path=root/'manifest.json';manifest=json.loads(manifest_path.read_text());manifest['producer_commit']=commit
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');(root/'source-record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
excluded={'asset-package.zip','package-verification.json','SHA256SUMS.txt'}
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in excluded)
(root/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(root).as_posix()}\n' for p in files));files.append(root/'SHA256SUMS.txt')
package=root/'asset-package.zip'
with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in files:z.write(p,p.relative_to(root).as_posix())
with zipfile.ZipFile(package) as z:
 assert z.testzip() is None;assert set(z.namelist())=={p.relative_to(root).as_posix() for p in files}
 with tempfile.TemporaryDirectory(prefix='steam-unzip-') as directory:
  z.extractall(directory)
  for p in files:assert (Path(directory)/p.relative_to(root)).read_bytes()==p.read_bytes(),p
  assert {p.relative_to(directory).as_posix() for p in Path(directory).rglob('*') if p.is_file()}==set(z.namelist())
result={'status':'VERIFIED','files':len(files),'zip_bytes':package.stat().st_size,'zip_sha256':sha(package),'producer_commit':commit,'checks':['real Git producer matches all recipe/tool bytes','complete extraction','CRC','member set','all extracted file bytes match live files']}
(root/'package-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
