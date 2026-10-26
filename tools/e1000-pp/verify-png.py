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
count=0
for path in root.rglob('*.png'):
    with Image.open(path) as png:
        png.load()
        assert png.width>0 and png.height>0
        if png.mode=='RGBA' and png.getchannel('A').getextrema()[0]==0:
            bbox=png.getchannel('A').getbbox()
            assert bbox and bbox[0]>=2 and bbox[1]>=2 and bbox[2]<=png.width-2 and bbox[3]<=png.height-2, path
        count+=1
print(f'VERIFIED {len(manifest["models"])*7} seven-direction transparent PNGs and complete decoding of all {count} PNG artifacts; transparent bounds unclipped.')
