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
recipes=['Map3DGreenTram.swift','Map3DGreenCommuter.swift','Map3DThreeCarUrban.swift']
common=['Sources/GamePresentation/Map3DModels.swift','Sources/GamePresentation/Map3DGeometry.swift','Sources/GamePresentation/Map3DStationKitGeometry.swift','Sources/GamePresentation/Map3DCivicKitGeometry.swift','Sources/GamePresentation/Map3DScene.swift','Sources/GamePresentation/Map3DBuildings.swift','tools/station-kit/renderer.js','tools/station-kit/package.mjs']
producer_files = [source/'Sources/GamePresentation'/name for name in recipes] + [source/name for name in common] + sorted((source/'tools/train-colors').glob('*'))
for path in producer_files:
    if not path.is_file(): continue
    rel=path.relative_to(source).as_posix()
    committed=subprocess.check_output(['git','show',f'{commit}:{rel}'],cwd=source)
    assert committed==path.read_bytes(), f'Producer mismatch: {rel}'

record = {
    'producer_repository': 'a91453/railway-game-ios',
    'producer_commit': commit,
    'recipes_sha256': {'Sources/GamePresentation/'+name:sha(source/'Sources/GamePresentation'/name) for name in recipes},
    'baseline_producer_commit': '2b2bfab2ae6f2a94407c8acd0224516d590a07f5',
    'change': 'vertex colours only; every vertex position, normal, triangle order/count, glow and alpha equal to baseline',
    'palette': {'tram':'tileWhite / shopAwnings[0] / tankWhite', 'commuter':'tileWhite / trimBlue / roof', 'urban':'tileWhite / containers[2] / tankSteel'},
    'rebuild': 'tools/train-colors/README.md',
    'supplied_reference': 'owner requested all three trains be recoloured in the best game style; original shape references unchanged; no new images or source meshes',
    'other_source': 'project Map3DPalette / Map3DTrainStyle.glass; proportions inferred from supplied images; no identified engineering dimensions',
    'private_reference_use': 'prior native exports used only to prove geometry and normals unchanged; no raw mesh, texture or source image copied',
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
