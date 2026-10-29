"""Compare every existing output byte and full-vertex-field FNV, including KRTC."""
import json,sys,hashlib
from pathlib import Path
base,current,lock=map(Path,sys.argv[1:4])
a=json.loads((base/'manifest.json').read_text());b=json.loads((current/'manifest.json').read_text());bm={m['id']:m for m in b['models']};rows=[]
for m in a['models']:
 n=bm[m['id']]
 assert (base/m['native']).read_bytes()==(current/n['native']).read_bytes(),m['id']
 assert m['hash']==n['hash'],m['id']
 rows.append({'id':m['id'],'sha256':hashlib.sha256((base/m['native']).read_bytes()).hexdigest(),'FNV_all_fields':m['hash']})
assert len(rows)>=735,'incomplete baseline export'
old=json.loads(lock.read_text())['models'];inherited=[];unpinned=[]
for m in a['models']:
 if m['id'] not in old:unpinned.append(m['id'])
 elif old[m['id']]!={'hash':m['hash'],'triangles':m['triangles']}:inherited.append(m['id'])
report={'status':'VERIFIED','baseline_models':len(rows),'every_native_byte_and_vertex_field_unchanged':True,'inherited_lock_differences':inherited,'already_unpinned_baseline_ids':unpinned,'models':rows}
(current/'protected-existing.json').write_text(json.dumps(report,indent=2)+'\n')
print('VERIFIED',len(rows),'all existing payloads and full-field FNV;',len(inherited),'inherited lock mismatches preserved')
