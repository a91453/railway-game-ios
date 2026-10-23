#!/usr/bin/env python3
"""Decode every PNG and independently check alpha geometry against render metrics."""
import hashlib
import json
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'manifest.json').read_text())
count = 0
for model in manifest['models']:
    for direction, relative in model['views'].items():
        path = root / relative
        metric = model['view_metrics'][direction]
        with Image.open(path) as image:
            image.load()
            assert image.mode == 'RGBA' and image.size == (384, 384), path
            alpha = image.getchannel('A')
            assert alpha.getextrema() == (0, 255), path
            mask = alpha.point(lambda value: 255 if value > 16 else 0)
            bounds = mask.getbbox()
            pixels = sum(mask.histogram()[1:])
            assert list(bounds) == metric['visible_bounds'], path
            assert pixels == metric['opaque_pixels'] and pixels >= 20, path
            left, top, right, bottom = bounds
            assert left >= 2 and top >= 2 and right <= 382 and bottom <= 382, path
        assert hashlib.sha256(path.read_bytes()).hexdigest() == metric['sha256'], path
        count += 1
# Review sheets must decode too, including browser screenshots.
sheets = 0
for path in sorted((root / 'previews').glob('*.png')):
    with Image.open(path) as image:
        image.load()
        assert min(image.size) > 0, path
        sheets += 1
assert count == 196
report = {'status': 'VERIFIED', 'decoder': 'Pillow ' + Image.__version__,
          'seven_view_pngs': count, 'review_pngs': sheets,
          'checks': ['full RGBA decode', 'independent alpha count and bounds match renderer',
                     'transparent background, opaque geometry, unclipped', 'SHA-256']}
(root / 'image-decoding.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
