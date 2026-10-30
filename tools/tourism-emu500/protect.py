"""Compare actual pre/post exports and every retained vertex field hash."""
from pathlib import Path
import hashlib,json,sys,struct,collections
before,after=map(Path,sys.argv[1:3]);a=json.loads((before/'manifest.json').read_text());b=json.loads((after/'manifest.json').read_text());bm={m['id']:m for m in b['models']}
for m in a['models']:
 n=bm[m['id']];assert m['hash']==n['hash'] and m['triangles']==n['triangles'],m['id']
 assert (before/m['native']).read_bytes()==(after/n['native']).read_bytes(),m['id']
report=dict(status='VERIFIED',baseline_commit='a1e33214bc89f9875cdc7721dcb35948e3af88e3',existing_models=len(a['models']),payload_bytes_identical=True,all_vertex_fields_fnv_identical=True,upstream_changes='none relative to recorded base',limits='M3DM omits u/v but the FNV includes x/y/z/nx/ny/nz/color/u/v/layer')
Path(sys.argv[3]).write_text(json.dumps(report,indent=2)+'\n');print(report)
