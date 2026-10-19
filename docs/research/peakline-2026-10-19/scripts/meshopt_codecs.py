"""Count meshopt stream header bytes (vertex 0xa0=v0, 0xa1=v1; index 0xe0=v0, 0xe1=v1) per GLB/glTF."""
import json, struct, sys, os, collections
for p in sys.argv[1:]:
    b = open(p, 'rb').read()
    if b[:4] == b'glTF':
        n = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20 + n]); off = 20 + n
        bins = {}
        if off < len(b): m = struct.unpack('<I', b[off:off + 4])[0]; bins[0] = b[off + 8: off + 8 + m]
    else:
        j = json.load(open(p)); d = os.path.dirname(p); bins = {i: open(os.path.join(d, x['uri']), 'rb').read() for i, x in enumerate(j['buffers']) if 'uri' in x}
    c = collections.Counter()
    for v in j.get('bufferViews', []):
        e = v.get('extensions', {}).get('EXT_meshopt_compression') or v.get('extensions', {}).get('KHR_meshopt_compression')
        if not e: continue
        buf = bins.get(e['buffer']); h = buf[e.get('byteOffset', 0)] if buf else None
        c[(e['mode'], hex(h) if h is not None else None, e.get('filter', 'NONE'))] += 1
    print(os.path.basename(p), dict(c))
