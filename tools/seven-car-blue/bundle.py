"""Record the public producer commit, then ZIP and compare every member byte for byte."""
import hashlib
import json
import sys
import zipfile
import subprocess
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
commit = sys.argv[2]
assert len(commit) == 40 and all(c in '0123456789abcdef' for c in commit)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

source = Path(__file__).resolve().parents[2]
# Reject a fabricated / stale producer: every recipe and batch tool must be
# byte-identical to that real commit. Metadata cannot substitute for this.
producer_files = sorted(set([source/'tools/station-kit/package.mjs',source/'tools/station-kit/renderer.js'] + list((source/'Sources/GamePresentation').glob('Map3D*.swift')) + [p for p in (source/'tools/seven-car-blue').glob('*') if p.is_file()]))
for path in producer_files:
    if not path.is_file(): continue
    rel=path.relative_to(source).as_posix()
    committed=subprocess.check_output(['git','show',f'{commit}:{rel}'],cwd=source)
    assert committed==path.read_bytes(), f'Producer mismatch: {rel}'

record = {
    'producer_repository': 'a91453/railway-game-ios',
    'producer_commit': commit,
    'recipes': ['Sources/GamePresentation/Map3DSevenCarBlue.swift'],
    'recipe_sha256': {'Map3DSevenCarBlue.swift':sha(source/'Sources/GamePresentation/Map3DSevenCarBlue.swift')},
    'rebuild': 'tools/seven-car-blue/README.md',
    'supplied_reference': 'seven inline owner views: roof/front, four opposite full oblique views and two opposite side crops; all visually inspected; not available as local files, no invented image SHA',
    'other_source': 'existing project palette and closed low-level geometry; no previous vehicle body, chassis, cab or door recipe reused',
    'private_reference_commit': '7bbd1043f9649645cd7f1a0a14d4f68cee392b02',
    'private_base_commit': '7a94383baaf9ff672e78f4590012a61760ab9e54',
    'prototype_record': 'history/initial/source-record.json (actual local uncommitted prototype; no invented producer commit)',
    'private_reference_use': 'World rolling-stock catalog-2026-10.json / rail-3d/integration/formations.js and Taiwan garage-blender-v1/danhai.json inspected; danhai is Q-proportions with engineeringDimensionsM=null and cannot identify this seven-module train. No uniquely matching engineering dimensions. No private mesh/image/texture copied.',
    'producer_files_sha256': {p.relative_to(source).as_posix():sha(p) for p in producer_files if p.is_file()},
    'limitations': ['static art only', 'dimensions are proportional display estimates', 'exact type and concealed running gear unknown; twenty-eight display axles are an assumption', 'no device Metal / animation / performance verification'],
}
manifest_path=root/'manifest.json'
manifest=json.loads(manifest_path.read_text())
manifest['producer_commit']=commit
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(root / 'source-record.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
excluded = {'asset-package.zip', 'package-verification.json', 'SHA256SUMS.txt'}
files = sorted(p for p in root.rglob('*') if p.is_file() and p.name not in excluded)
(root / 'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(root).as_posix()}\n' for p in files))
files.append(root / 'SHA256SUMS.txt')
package = root / 'asset-package.zip'
with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in files:
        archive.write(path, path.relative_to(root).as_posix())
with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == {p.relative_to(root).as_posix() for p in files}
    with tempfile.TemporaryDirectory(prefix='urban-unzip-') as directory:
        archive.extractall(directory)
        for path in files:
            rel=path.relative_to(root)
            assert (Path(directory)/rel).read_bytes() == path.read_bytes(), path
        assert {p.relative_to(directory).as_posix() for p in Path(directory).rglob('*') if p.is_file()} == set(archive.namelist())
result = {'status': 'VERIFIED', 'files': len(files), 'zip_bytes': package.stat().st_size,
          'zip_sha256': sha(package), 'producer_commit': commit,
          'checks': ['complete ZIP extraction', 'CRC', 'each archive member equals its live file bytes']}
(root / 'package-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result))
