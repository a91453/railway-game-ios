"""Pinned inputs around shared delivery; does not create geometry or a viewer.
python3 tools/tra-r100/deliver.py RUN DEST PRODUCER
"""
from pathlib import Path
import hashlib
import json
import runpy
import shutil
import subprocess
import sys

run,dest=map(lambda p:Path(p).resolve(),sys.argv[1:3]);producer=sys.argv[3];repo=Path.cwd()
def pinned(path):return subprocess.check_output(['git','show',producer+':'+path])
inputs=['docs/art/tra-r100/sources.json','docs/art/tra-r100/status.json',
        'docs/art/tra-r100/README.md','docs/art/tra-r100/IDENTITY.md',
        'docs/art/tra-r100/blue-sources.json','tools/tra-r100/formation.json',
        'tools/tra-r100/configuration.json','tools/tra-r100/build.sh',
        'tools/tra-r100/review.mjs','tools/tra-r100/curate.py','tools/tra-r100/deliver.py']
for path,name in [('docs/art/tra-r100/sources.json','source-record.json'),
                  ('docs/art/tra-r100/status.json','status.json')]:
    (run/name).write_bytes(pinned(path))
spec=dict(repo='.',producer=producer,previous_producer='No accepted accurate R100 predecessor; legacy shared hood is a substitute.',
    rebuild='''# Swift 6.4, Node/Playwright/Chromium, Python/Pillow and Blender as in README
tools/tra-r100/build.sh /tmp/r100-run
node tools/tra-r100/review.mjs /tmp/r100-run
python3 tools/tra-r100/curate.py /tmp/r100-run /tmp/r100-overview.png
python3 tools/tra-r100/deliver.py /tmp/r100-run DEST/tra-r100/revision-1 '''+producer,
    sources='source-record.json',status='status.json',license_files=[],
    pngs=['selected/'+p.name for p in sorted((run/'selected').glob('*.png'))],
    metadata_inputs={p:hashlib.sha256(pinned(p)).hexdigest() for p in inputs})
assert len(spec['pngs'])<=20
runpy.run_path(str(repo/'tools/train-models/deliver.py'))['deliver'](run,spec,dest)
for source,name in [('tools/tra-r100/configuration.json','configuration.json'),
                    ('tools/tra-r100/formation.json','formation.json'),
                    ('docs/art/tra-r100/IDENTITY.md','IDENTITY.md'),
                    ('docs/art/tra-r100/blue-sources.json','blue-sources.json')]:
    (dest/name).write_bytes(pinned(source))
for name in ['geometry-verification.json','r100-verification.json','swift-assembly-verification.json','independent-glb.json']:
    if (run/name).exists():shutil.copyfile(run/name,dest/name)
(dest/'DELIVERY-SPEC.json').write_text(json.dumps(spec,indent=2,ensure_ascii=False)+'\n')
with (dest/'README.md').open('ab') as f:f.write(b'\n---\n\n'+pinned('docs/art/tra-r100/README.md'))
files=sorted(p for p in dest.rglob('*') if p.is_file() and p.name!='SHA256SUMS.txt')
(dest/'SHA256SUMS.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(dest).as_posix() for p in files)+'\n')
print(dest)
