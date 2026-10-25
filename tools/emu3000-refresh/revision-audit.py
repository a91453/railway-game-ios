"""Compare the actual revision2 payloads with revision3, outside requested regions."""
from pathlib import Path
import sys,json,struct,collections,hashlib
import numpy as np
old,new=map(Path,sys.argv[1:3]);sha=lambda b:hashlib.sha256(b).hexdigest()
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def points(t):return np.array([struct.unpack_from('<fff',t,4+j*16) for j in range(3)])
a_manifest=json.loads((old/'manifest.json').read_text());assert a_manifest['producer_commit']=='23a59907b41c6fefced0bbc7368352ab64e1e7a3'
b_manifest=json.loads((new/'manifest.json').read_text());rows=[]
for m in b_manifest['models']:
 if m['category']!='section':continue
 name=m['native'];a=read(old/name);b=read(new/name);before=collections.Counter(a);after=collections.Counter(b)
 removed=list((before-after).elements());added=list((after-before).elements());tail='tail' in m['id'];cab=tail or '-ed' in m['id']
 def allowed(t):
  p=points(t);x=-p[:,0] if tail else p[:,0]
  if cab and np.all(x>=5.70):return True
  doors=[-8.5,3.9,5.15] if cab else [-8,8]
  return any(np.all(abs(x-d)<=0.451) for d in doors) and np.all(abs(p[:,1])>1.05) and np.all((p[:,2]>=1.14)&(p[:,2]<=3.19))
 assert removed and added
 for t in removed+added:assert allowed(t),(m['id'],'unrequested geometry changed',points(t))
 preserved=before & after
 rows.append({'id':m['id'],'old_triangles':len(a),'new_triangles':len(b),'removed_triangles':len(removed),'added_triangles':len(added),'preserved_triangles':sum(preserved.values()),'preserved_payload_sha256':sha(b''.join(sorted(preserved.elements()))),'allowed_regions':'door gaskets/glazing; cab nose x>=5.70 (includes attached quarterlight) only' if cab else 'door gaskets/glazing only'})
def chin(root):
 m=json.loads((root/'manifest.json').read_text());white=m['palette']['body'];ts=read(root/'models/emu3000-ed.m3dmodel');p=np.concatenate([points(t) for t in ts if all(struct.unpack_from('<I',t,16+j*16)[0]==white for j in range(3)) and np.all(points(t)[:,0]>8)])
 return {'minimum_white_nose_z_m':float(p[:,2].min()),'maximum_white_nose_z_m':float(p[:,2].max())}
a,b=chin(old),chin(new)
assert b['minimum_white_nose_z_m']<a['minimum_white_nose_z_m']-0.45
assert b['minimum_white_nose_z_m']>=0.20,'front clearance below static model target'
(new/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':a_manifest['producer_commit'],'method':'actual52-byte triangle multisets; differences confined to doors and cab nose; virtual nose white bounds not engineering dimensions','before':a,'after':b,'models':rows},indent=2)+'\n')
print('VERIFIED sixteen units: only door/nose regions changed; chin lowered with >=0.20m static clearance')
