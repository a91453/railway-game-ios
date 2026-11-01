"""R200's small reproducible input wrapper around the shared delivery tool.
Run from the public checkout: python3 tools/tra-r200/deliver.py RUN DEST R1_RUN PRODUCER.
R1_RUN must be rendered from the genuine, unaccepted 65464b23 producer.
"""
from pathlib import Path
import hashlib
import json
import runpy
import shutil
import subprocess
import sys


def deliver(run, dest, previous, producer):
    repo = Path.cwd()
    run, dest, previous = map(lambda p: Path(p).resolve(), (run, dest, previous))
    def pinned(path):
        return subprocess.check_output(['git', 'show', producer+':'+path])
    inputs = ['docs/art/tra-r200/sources.json', 'docs/art/tra-r200/status.json',
              'docs/art/tra-r200/README.md', 'tools/tra-r200/configuration.json',
              'tools/tra-r200/curate.py', 'tools/tra-r200/review.mjs',
              'tools/tra-r200/deliver.py']
    before = ['tra-r200-r216-locomotive-'+view+'.png' for view in ['isometric', 'left', 'front']]
    for source, name in [('sources.json', 'source-record.json'), ('status.json', 'status.json')]:
        (run/name).write_bytes(pinned('docs/art/tra-r200/'+source))
    spec = dict(repo='.', producer=producer,
        previous_producer='65464b23fc0b26058521d362555b9a0d8b550c98',
        rebuild='''# Render the real R1 from its producer as documented in README first.
# Then run these in the R2 producer checkout, with Swift 6.4 on PATH:
tools/tra-r200/build.sh /tmp/r200-r2
NODE_GLOBAL=/path/to/node_modules/ CHROMIUM_PATH=/usr/bin/chromium node tools/tra-r200/review.mjs /tmp/r200-r2
python3 tools/tra-r200/curate.py /tmp/r200-r2 /tmp/overview.png /tmp/r200-r1
python3 tools/tra-r200/deliver.py /tmp/r200-r2 DEST/tra-r200/revision-2 /tmp/r200-r1 PRODUCER''',
        sources='source-record.json', status='status.json', license_files=[],
        pngs=['selected/'+p.name for p in sorted((run/'selected').glob('*.png'))],
        metadata_inputs={p: hashlib.sha256(pinned(p)).hexdigest() for p in inputs},
        previous_preview_sha256={p: hashlib.sha256((previous/'review/color'/p).read_bytes()).hexdigest() for p in before})
    spec['rebuild'] = spec['rebuild'].replace(' PRODUCER', ' '+producer)
    tool = runpy.run_path(str(repo/'tools/train-models/deliver.py'))
    tool['deliver'](run, spec, dest)
    (dest/'DELIVERY-SPEC.json').write_text(json.dumps(spec, ensure_ascii=False, indent=2)+'\n')
    (dest/'configuration.json').write_bytes(pinned('tools/tra-r200/configuration.json'))
    for name in ['geometry-verification.json', 'r200-verification.json']:
        shutil.copyfile(run/name, dest/name)
    with (dest/'README.md').open('ab') as f:
        f.write(b'\n\n---\n\n'+pinned('docs/art/tra-r200/README.md'))
    files = sorted(p for p in dest.rglob('*') if p.is_file() and p.name!='SHA256SUMS.txt')
    (dest/'SHA256SUMS.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(dest).as_posix() for p in files)+'\n')
    return dest


if __name__ == '__main__':
    print(deliver(*sys.argv[1:]))
