#!/usr/bin/env python3
"""Build a deterministic private download bundle from the verified outputs."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import sys

root = Path(sys.argv[1]).resolve()
if not (root / 'verification.json').is_file() or not (root / 'remix-provenance.json').is_file():
    raise SystemExit('Verification and private provenance are required before bundling.')
archive = root / 'residential-kit-2026-10-21.zip'
paths = sorted(p for p in root.rglob('*') if p.is_file() and p != archive and p.name != 'render-cache.json')
with ZipFile(archive, 'w', compression=ZIP_DEFLATED, compresslevel=9) as zip_file:
    for path in paths:
        info = ZipInfo(path.relative_to(root).as_posix(), date_time=(2026, 10, 21, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        zip_file.writestr(info, path.read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)
print(f'Bundled {len(paths)} verified output files: {archive}')
