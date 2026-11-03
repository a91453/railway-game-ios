"""Compare actual runtime order, every vertex-field FNV, and native bytes.
Usage: protect.py CLEAN_RUN CANDIDATE_RUN REPORT
Both runs must use tools/tra-emu700/inventory.sh (read actual standard/studies).
"""
import hashlib,json,sys
from pathlib import Path
a,b=map(Path,sys.argv[1:3]);report=Path(sys.argv[3])
ma,mb=[json.loads((p/'manifest.json').read_text())['models'] for p in [a,b]]
ia,ib=[json.loads((p/'runtime-inventory.json').read_text()) for p in [a,b]]
assert ia['standard']==ib['standard'],'standard order changed'
assert ib['studies'][:len(ia['studies'])]==ia['studies'],'old study order changed'
byid={m['id']:m for m in mb};rows=[]
for m in ma:
 n=byid[m['id']];assert m['hash']==n['hash'],m['id']
 x=(a/m['native']).read_bytes();y=(b/n['native']).read_bytes();assert x==y,m['id']
 rows.append({'id':m['id'],'hash':m['hash'],'sha256':hashlib.sha256(x).hexdigest(),'bytes':len(x)})
assert len(mb)==len(ma)+8
report.write_text(json.dumps({'status':'VERIFIED','scope':'real standard/studies order, all vertex fields FNV and native bytes; no device/performance claim','existing_models':rows,'added':sorted(set(byid)-{m['id'] for m in ma})},indent=2)+'\n')
print('Protected',len(rows),'actual runtime models; added 8 studies only')
