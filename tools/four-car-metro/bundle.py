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
producer_files = sorted(set([source/'tools/station-kit/package.mjs',source/'tools/station-kit/renderer.js'] + list((source/'Sources/GamePresentation').glob('Map3D*.swift')) + [p for p in (source/'tools/four-car-metro').glob('*') if p.is_file()]))
for path in producer_files:
    if not path.is_file(): continue
    rel=path.relative_to(source).as_posix()
    committed=subprocess.check_output(['git','show',f'{commit}:{rel}'],cwd=source)
    assert committed==path.read_bytes(), f'Producer mismatch: {rel}'

record = {
    'producer_repository': 'a91453/railway-game-ios',
    'producer_commit': commit,
    'recipes': ['Sources/GamePresentation/Map3DFourCarMetro.swift'],
    'recipe_sha256': {'Map3DFourCarMetro.swift':sha(source/'Sources/GamePresentation/Map3DFourCarMetro.swift')},
    'rebuild': 'tools/four-car-metro/README.md',
    'supplied_reference': 'five inline owner views: roof/front, two opposite side crops, two opposite full oblique views; all visually inspected; not available as local files, no invented image SHA',
    'other_source': 'existing project palette and closed low-level geometry; no previous vehicle body, chassis, cab or door recipe reused',
    'private_reference_commit': '60a76270cf3be9517100c2f3bbfd0dd87051e88f',
    'private_reference_use': 'OpenWorld train-model-specs.js, world rolling-stock catalog-2026-10.json and procedural MODEL_CATALOG.json inspected; no uniquely matching dimensions. No private mesh/image/texture copied.',
    'producer_files_sha256': {p.relative_to(source).as_posix():sha(p) for p in producer_files if p.is_file()},
    'limitations': ['static art only', 'dimensions are proportional display estimates', 'no device Metal / animation / performance verification'],
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
