"""Compare real exported existing payloads and every vertex-field FNV, without rewriting locks."""
import json,sys
from pathlib import Path
base,current=map(Path,sys.argv[1:3]);a=json.loads((base/'manifest.json').read_text());b=json.loads((current/'manifest.json').read_text());bm={m['id']:m for m in b['models']};rows=[]
for m in a['models']:
 if m['id'].startswith('kaohsiung-'):continue
 n=bm[m['id']]
 assert (base/m['native']).read_bytes()==(current/n['native']).read_bytes(),m['id']
 assert m['hash']==n['hash'],m['id']
 rows.append(m['id'])
assert len(rows)>=688,'incomplete protected-model export'
report={'status':'VERIFIED','protected_models':len(rows),'native_bytes_equal':True,'all_vertex_fields_FNV_equal':True,'ids':rows}
(current/'protected-existing.json').write_text(json.dumps(report,indent=2)+'\n');print('VERIFIED',len(rows),'existing payloads / full-field FNV')
