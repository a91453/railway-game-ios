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
producer_files = sorted(set([source/'tools/station-kit/package.mjs',source/'tools/station-kit/renderer.js'] + list((source/'Sources/GamePresentation').glob('Map3D*.swift')) + [p for p in (source/'tools/five-section-lrt').glob('*') if p.is_file()]))
for path in producer_files:
    if not path.is_file(): continue
    rel=path.relative_to(source).as_posix()
    committed=subprocess.check_output(['git','show',f'{commit}:{rel}'],cwd=source)
    assert committed==path.read_bytes(), f'Producer mismatch: {rel}'

record = {
    'producer_repository': 'a91453/railway-game-ios',
    'producer_commit': commit,
    'recipe': 'Sources/GamePresentation/Map3DFiveSectionLRT.swift',
    'recipe_sha256': sha(source / 'Sources/GamePresentation/Map3DFiveSectionLRT.swift'),
    'rebuild': 'tools/five-section-lrt/README.md',
    'supplied_reference': 'five inline chat images; visually inspected; not stored as local files',
    'other_source': 'project Map3DPalette / shaded Map3DPalette.glazing; 34m approximate scale from private source citing https://takao.kcg.gov.tw/article/2127, not manufacturer dimensions; three double-axle bogies is a hidden-geometry assumption',
    'private_reference_commit': 'ead61ab0dc2e40d40eb2a6d2a0fb05a5c83129d8',
    'private_reference_use': 'taiwan-rail-reference-clean/source/rail-3d/README.md, integration/FORMATIONS.md and formations.js checked: five sections, 34m / 2.65m approximate scale; garage-blender-v1/caf.json checked but its door count / Q-proportions not applied; no mesh/image/texture copied',
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
