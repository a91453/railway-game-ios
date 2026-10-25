"""Compare actual pre/post GamePresentation payloads, not recipe constants."""
import hashlib,json,sys
from pathlib import Path
before,after,out=map(Path,sys.argv[1:4]);sha=lambda b:hashlib.sha256(b).hexdigest()
a={m['id']:m for m in json.loads((before/'fingerprints.json').read_text())};b={m['id']:m for m in json.loads((after/'fingerprints.json').read_text())};rows=[]
for name,m in a.items():
 if name.startswith('set-emu3000-'):continue
 assert name in b,('lost existing model',name)
 old=(before/m['payload']).read_bytes();new=(after/b[name]['payload']).read_bytes()
 assert old==new,('existing geometry/color/layer changed',name)
 rows.append({'id':name,'triangles':m['triangles'],'payload_sha256':sha(old)})
result={'status':'VERIFIED','before_commit':'85d9aa359dfcd6213f76a6559abebd9155806e97','unchanged_model_count':len(rows),'checked':'each Float32 position/color/layer byte of every pre-existing non-EMU model; normals derive from unchanged triangles','models':rows}
(out/'coexistence-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('VERIFIED',len(rows),'existing non-EMU models unchanged')
