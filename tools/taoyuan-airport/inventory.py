"""Compare actual inventories, including models absent from the old lock.
Usage: inventory.py BEFORE_JSON AFTER_JSON BEFORE_EXPORT AFTER_EXPORT REPORT
Inventories are the exporter --lock output, never installed as a replacement lock.
"""
import hashlib,json,sys
from pathlib import Path
before,after=map(lambda p:json.loads(Path(p).read_text())['models'],sys.argv[1:3])
a,b=map(Path,sys.argv[3:5]);rows=[]
for key,record in before.items():
 assert after[key]==record,('vertex fields changed',key)
 x=(a/'models'/f'{key}.m3dmodel').read_bytes();y=(b/'models'/f'{key}.m3dmodel').read_bytes()
 assert x==y,('payload bytes changed',key)
 rows.append({'id':key,'payload_bytes':len(x),'sha256':hashlib.sha256(x).hexdigest(),**record})
new=sorted(set(after)-set(before));assert all(k.startswith('taoyuan-airport-') for k in new)
Path(sys.argv[5]).write_text(json.dumps({'status':'VERIFIED','existing':rows,'added':new,'limits':'all runtime standard/studies vertex fields and native payload bytes; not device performance'},indent=2)+'\n')
print('VERIFIED',len(rows),'existing runtime models; added',len(new))
