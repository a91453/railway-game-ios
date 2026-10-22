"""Record the public producer commit, then ZIP and compare every member byte for byte."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
commit = sys.argv[2]
assert len(commit) == 40 and all(c in '0123456789abcdef' for c in commit)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

source = Path(__file__).resolve().parents[2]
record = {
    'producer_repository': 'a91453/railway-game-ios',
    'producer_commit': commit,
    'recipe': 'Sources/GamePresentation/Map3DGreenCommuter.swift',
    'recipe_sha256': sha(source / 'Sources/GamePresentation/Map3DGreenCommuter.swift'),
    'rebuild': 'tools/green-commuter/README.md',
    'supplied_reference': 'five inline chat images; visually inspected; not stored as local files',
    'other_source': 'project Map3DPalette / Map3DTrainStyle.glass / 20 m commuter-car display scale',
    'private_reference_use': 'existing project commuter cab and preceding green tram used for style comparison; no mesh/image/texture copied',
}
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
    for path in files:
        assert archive.read(path.relative_to(root).as_posix()) == path.read_bytes(), path
result = {'status': 'VERIFIED', 'files': len(files), 'zip_bytes': package.stat().st_size,
          'zip_sha256': sha(package), 'producer_commit': commit,
          'checks': ['complete ZIP extraction', 'CRC', 'each archive member equals its live file bytes']}
(root / 'package-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result))
