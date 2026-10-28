import json
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text())
for model in manifest['models']:
    for name, path in model['views'].items():
        with Image.open(root / path) as png:
            png.load()
            assert png.mode == 'RGBA' and png.size == (512, 512), (model['id'], name)
            lo, hi = png.getchannel('A').getextrema()
            assert lo == 0 and hi == 255, (model['id'], name)
print(f'VERIFIED {sum(len(model["views"]) for model in manifest["models"])} PNG files fully decoded as nonblank transparent RGBA.')
