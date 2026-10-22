"""Prove the geometry audit rejects actual missing/reversed native triangles."""
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
audit = Path(__file__).with_name('geometry-audit.mjs').resolve()
results = []
with tempfile.TemporaryDirectory(prefix='urban-mutation-') as directory:
    target = Path(directory)
    shutil.copytree(root/'models', target/'models')
    shutil.copy(root/'manifest.json', target/'manifest.json')
    model = target/'models/urban-three-leading.m3dmodel'
    original = model.read_bytes()
    count, size = struct.unpack_from('<II', original, 8)
    start = 16 + (size+3)//4*4
    for mode in ['missing_triangle', 'inverted_triangle']:
        data = bytearray(original)
        if mode == 'missing_triangle':
            del data[start:start+52]
            struct.pack_into('<I', data, 8, count-1)
        else:
            first = data[start+4:start+20]
            data[start+4:start+20] = data[start+20:start+36]
            data[start+20:start+36] = first
        model.write_bytes(data)
        run = subprocess.run(['node', str(audit), str(target)], capture_output=True, text=True)
        assert run.returncode != 0, f'Audit accepted {mode}'
        assert 'open or inconsistently wound welded edges' in run.stderr, run.stderr
        (root/f'{mode}-rejection.log').write_text(run.stderr)
        results.append({'mutation': mode, 'exit': run.returncode, 'rejected': True})
(root/'mutation-verification.json').write_text(json.dumps({'status': 'VERIFIED', 'checks': results}, indent=2)+'\n')
print('VERIFIED missing and inverted triangles are rejected by geometry audit.')
