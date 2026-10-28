"""Curate one new asset round. Never overwrites an existing round.

python3 tools/train-models/deliver.py RUN SPEC.json DEST
SPEC fields: repo, producer, rebuild, sources, status, pngs (RUN-relative paths).
Run asset_guard in the destination repository after staging the full PR.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from PIL import Image


def verify_png(path):
    with Image.open(path) as image:
        image.load()
        if image.format != 'PNG' or image.mode != 'RGBA':
            raise ValueError(f'PNG must be RGBA: {path}')
        alpha = image.getchannel('A')
        if alpha.getextrema() != (0, 255):
            raise ValueError(f'PNG must be nonblank and transparent: {path}')
        box = alpha.getbbox()
        if not box or min(box[:2]) < 2 or box[2] > image.width-2 or box[3] > image.height-2:
            raise ValueError(f'PNG clipped: {path}')
    if path.stat().st_size > 2*1024*1024:
        raise ValueError(f'PNG exceeds 2 MiB: {path}')


def deliver(run, spec, dest):
    run, dest = Path(run).resolve(), Path(dest).resolve()
    if dest.exists() or dest == run or run in dest.parents:
        raise ValueError('Use a new destination outside RUN; existing rounds are never overwritten')
    if any(p.lower() in {'history', 'old', 'backup'} for p in dest.parts):
        raise ValueError('Forbidden archive directory')
    if dest.name != 'final' and not (dest.name.startswith(('revision-', 'candidate-')) and dest.name.split('-')[-1].isdigit()):
        raise ValueError('Destination must be revision-N, candidate-N or final')
    repo = Path(spec['repo']).resolve()
    producer = spec['producer']
    if len(producer) != 40 or any(c not in '0123456789abcdef' for c in producer):
        raise ValueError('Producer must be a full commit SHA')
    subprocess.run(['git', '-C', str(repo), 'cat-file', '-e', producer+'^{commit}'], check=True)
    subprocess.run(['git', '-C', str(repo), 'diff', '--quiet', producer, '--', 'Sources', 'tools'], check=True)
    if subprocess.check_output(['git', '-C', str(repo), 'ls-files', '--others', '--exclude-standard', '--', 'Sources', 'tools'], text=True).strip():
        raise ValueError('Uncommitted new Sources/tools files are not part of the producer')
    if not spec['rebuild'].strip():
        raise ValueError('Missing rebuild command')
    pngs = spec['pngs']
    if not pngs or len(pngs) > 21 or len(set(pngs)) != len(pngs):
        raise ValueError('Choose 1–21 distinct PNGs for the whole model round')
    manifest = json.loads((run/'manifest.json').read_text())
    if not manifest['models']:
        raise ValueError('Empty model delivery')

    def source(relative):
        if not isinstance(relative, str) or Path(relative).is_absolute() or '..' in Path(relative).parts:
            raise ValueError(f'Unsafe relative file: {relative}')
        path = (run/relative).resolve()
        if path == run or run not in path.parents or not path.is_file():
            raise ValueError(f'Not a file inside RUN: {relative}')
        return path

    files = set(pngs)
    for name in pngs:
        if Path(name).suffix.lower() != '.png':
            raise ValueError('Preview selection must contain PNGs')
        verify_png(source(name))
    for m in manifest['models']:
        for key in ['native', 'glb']:
            files.add(m[key])
        if m.get('assembly_payload'):
            files.add(m['assembly_payload'])
        # Drop views of unselected previews rather than publishing broken links.
        if 'views' in m:
            m['views'] = {k: v for k, v in m['views'].items() if v in pngs}
    sources = source(spec['sources'])
    record = json.loads(sources.read_text())
    for key in ['origin', 'date', 'license', 'public_use']:
        if not record.get(key):
            raise ValueError(f'Source record missing {key}')
    status = json.loads(source(spec['status']).read_text())
    for key in ['asset', 'appearance', 'integration', 'device']:
        entry = status[key]
        if entry['status'] not in ['VERIFIED', 'UNVERIFIED'] or (entry['status'] == 'VERIFIED' and not entry.get('evidence')):
            raise ValueError(f'Invalid completion evidence: {key}')
    if status['appearance']['status'] == 'VERIFIED' and status['appearance'].get('accepted_producer') != producer:
        raise ValueError('Appearance acceptance must identify this producer')
    # License texts are copied explicitly if third-party material is included.
    files.update(spec.get('license_files', []))
    for name in files:
        path = source(name)
        if path.suffix.lower() == '.zip' or any(p.lower() in {'history', 'old', 'backup'} for p in Path(name).parts):
            raise ValueError('No ZIP or archive copies')
        if path.stat().st_size > 50*1024*1024:
            raise ValueError(f'File exceeds 50 MiB: {path}')
    if sum(source(name).stat().st_size for name in files) > 200*1024*1024:
        raise ValueError('Round exceeds 200 MiB; obtain owner authorization separately')
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Build the complete round before publishing it, so rejected runs leave no
    # partial round and the previous round's files remain untouched.
    with tempfile.TemporaryDirectory(dir=dest.parent, prefix='.train-delivery-') as temp:
        staging = Path(temp)
        for name in sorted(files):
            target = staging/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source(name), target)
        manifest.update(producer_commit=producer, previews=pngs, model_count=len(manifest['models']))
        (staging/'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+'\n')
        (staging/'source-record.json').write_text(json.dumps(record, indent=2, ensure_ascii=False)+'\n')
        (staging/'status.json').write_text(json.dumps(status, indent=2, ensure_ascii=False)+'\n')
        (staging/'SOURCE.md').write_text('\n'.join(f'- {k}: {record[k]}' for k in ['origin', 'date', 'license', 'public_use'])+'\n')
        (staging/'README.md').write_text(
            f'# {dest.parent.name} / {dest.name}\n\nProducer: `{producer}`\n\n'
            f'Rebuild from the public repository at that commit:\n\n```sh\n{spec["rebuild"]}\n```\n\n'
            f'Previous producer: {spec.get("previous_producer", "new model; no previous delivery")}\n\n'
            'See source-record.json, SOURCE.md and status.json. This round keeps the latest heavy files. '
            'Older rounds retain PNG/README/source records; recover models by their producer commit. '
            'index.html is a self-contained WebGL inspector; its PNG download renders the current view. '
            'Selected reference previews are listed in manifest.json. No ZIP.\n')
        subprocess.run(['node', str(Path(__file__).with_name('inspect.mjs')), str(staging), str(staging/'index.html')], check=True)
        paths = [p for p in staging.rglob('*') if p.is_file()]
        if any(p.stat().st_size > 50*1024*1024 for p in paths) or sum(p.stat().st_size for p in paths) > 200*1024*1024:
            raise ValueError('Final round including embedded viewer exceeds size limits')
        sums = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(staging).as_posix()}' for p in sorted(paths)]
        (staging/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n')
        staging.rename(dest)
    return dest


if __name__ == '__main__':
    print(deliver(sys.argv[1], json.loads(Path(sys.argv[2]).read_text()), sys.argv[3]))
