"""Compare actual standard+studies inventories, including unlocked runtime IDs.
Both manifests must come from an exporter enumerating the entire runtime, not
from a guessed --all switch. Ten-field FNV and native bytes are checked.
"""
from pathlib import Path
import json,sys,hashlib
before,after,out=map(Path,sys.argv[1:])
a=json.loads((before/'manifest.json').read_text());b=json.loads((after/'manifest.json').read_text())
old={m['id']:m for m in a['models']};new={m['id']:m for m in b['models']}
assert len(old)==len(a['models']) and len(new)==len(b['models'])
rows=[]
for key,m in old.items():
 n=new[key];assert m['hash']==n['hash'],('ten-field FNV changed',key)
 x=(before/m['native']).read_bytes();y=(after/n['native']).read_bytes();assert x==y,('native bytes changed',key)
 rows.append({'id':key,'bytes':len(x),'sha256':hashlib.sha256(x).hexdigest(),'all_vertex_fields_fnv':m['hash']})
added=sorted(set(new)-set(old));assert len(added)==8 and all(k.startswith('tra-emu700-') for k in added)
out.write_text(json.dumps({'status':'VERIFIED','existing_count':len(rows),'existing_models':rows,'added':added,'limits':'FNV over x/y/z/nx/ny/nz/color/u/v/layer plus native bytes; no device memory certification'},indent=2)+'\n')
print('VERIFIED',len(rows),'existing runtime models')
