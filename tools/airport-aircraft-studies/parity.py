#!/usr/bin/env python3
"""parity.py PYTHON_PACK SWIFT_EXPORT: every model the Swift recipes make is,
triangle for triangle, the one produce.py wrote (points within 3 mm, the same
colours and glow flags). The scenes are previews only and have no Swift recipe."""
import json, struct, sys
from pathlib import Path

def read(path):
    b = path.read_bytes(); magic, major, minor, count, length = struct.unpack_from('<4sHHII', b, 0)
    assert magic == b'M3DM' and (major, minor) == (1, 0)
    at = 16 + (length + 3)//4*4; out = []
    for i in range(count):
        flag, = struct.unpack_from('<I', b, at); pts = [struct.unpack_from('<fffI', b, at+4+j*16) for j in range(3)]
        out.append((flag, pts)); at += 52
    return out

pack, export = Path(sys.argv[1]), Path(sys.argv[2]); bad = 0; checked = 0
for m in json.loads((pack/'manifest.json').read_text())['models']:
    if '-scene-' in m['id']: continue
    a, b = read(pack/m['native']), read(export/(m['id']+'.m3dmodel')); checked += 1
    if len(a) != len(b): print('COUNT', m['id'], len(a), len(b)); bad += 1; continue
    worst = 0
    for (fa, pa), (fb, pb) in zip(a, b):
        if fa != fb or any(p[3] != q[3] for p, q in zip(pa, pb)): worst = 9; break
        worst = max(worst, max(abs(p[k]-q[k]) for p, q in zip(pa, pb) for k in range(3)))
    if worst > .003: print('DIFFERS', m['id'], worst); bad += 1
print(checked, 'models compared,', bad, 'differ')
sys.exit(1 if bad else 0)
