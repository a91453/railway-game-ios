#!/usr/bin/env python3
"""Package the private batch and verify every ZIP member by decompression + SHA."""
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
repo = Path(__file__).resolve().parents[2]
if root == repo or repo in root.parents:
    raise SystemExit('Large bundles must be outside the public checkout')
sha = lambda data: hashlib.sha256(data).hexdigest()
manifest = json.loads((root / 'manifest.json').read_text())
source = {'repository': 'a91453/railway-game-ios',
          'generator_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
          'working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True).strip()),
          'recipe_sha256': manifest['recipe_sha256'],
          'notes': 'Recipe hashes identify the actual generated source, even for a rebuild from an uncommitted working tree.'}
(root / 'source.json').write_text(json.dumps(source, indent=2) + '\n')
archive = root / 'estate-kit-2026-10-23.zip'
skip = {archive.name, 'bundle-verification.json', 'files.sha256.json'}
files = sorted(p for p in root.rglob('*') if p.is_file() and p.name not in skip)
hashes = {str(p.relative_to(root)): sha(p.read_bytes()) for p in files}
(root / 'files.sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
files.append(root / 'files.sha256.json')
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
    for path in files:
        bundle.write(path, path.relative_to(root))
with zipfile.ZipFile(archive) as bundle:
    assert bundle.testzip() is None
    assert len(bundle.namelist()) == len(files) == len(set(bundle.namelist()))
    for path in files:
        assert bundle.read(str(path.relative_to(root))) == path.read_bytes(), path
report = {'status': 'VERIFIED', 'archive': archive.name, 'bytes': archive.stat().st_size,
          'sha256': sha(archive.read_bytes()), 'members': len(files),
          'checks': ['ZIP CRC', 'all members decompressed and byte-compared', 'per-file SHA-256 inventory']}
(root / 'bundle-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
