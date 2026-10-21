"""Independently decode all seven-view RGBA PNGs; never edits an image."""
import hashlib
import json
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text())
results = []
for model in manifest['models']:
    for direction, relative in model['views'].items():
        path = root / relative
        with Image.open(path) as image:
            image.load()
            assert image.mode == 'RGBA' and image.size == (384, 384), path
            alpha = image.getchannel('A')
            low, high = alpha.getextrema()
            assert low == 0 and high == 255, path
            pixels = sum(n for a, n in enumerate(alpha.histogram()) if a > 16)
            metric = model['view_metrics'][direction]
            assert pixels == metric['opaque_pixels'], path
            assert hashlib.sha256(path.read_bytes()).hexdigest() == metric['sha256'], path
            results.append({'path': relative, 'alpha_range': [low, high], 'pixels': pixels})
assert len(results) == 14
path = root / 'verification.json'
verification = json.loads(path.read_text())
verification['png_decode'] = {'status': 'VERIFIED', 'decoder': 'Pillow full RGBA decode', 'views': results}
path.write_text(json.dumps(verification, indent=2, ensure_ascii=False) + '\n')
print('VERIFIED 14 full RGBA decodes; transparent/opaque alpha and renderer pixel counts match.')
