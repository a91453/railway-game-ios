"""Revision4: independent same-index triangle check; only the low white cab chin moves."""
from pathlib import Path
import sys,json,struct,hashlib
import numpy as np
old,new=map(Path,sys.argv[1:3]);sha=lambda b:hashlib.sha256(b).hexdigest()
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def points(t):return np.array([struct.unpack_from('<fff',t,4+j*16) for j in range(3)])
a_manifest=json.loads((old/'manifest.json').read_text());assert a_manifest['producer_commit']=='e25474fffe42a98fd6cbc04b5f287485be72e097'
b_manifest=json.loads((new/'manifest.json').read_text());white=b_manifest['palette']['body'];rows=[]
for m in b_manifest['models']:
 if m['category']!='section':continue
 a=read(old/m['native']);b=read(new/m['native']);assert len(a)==len(b);tail='tail' in m['id'];cab=tail or '-ed' in m['id'];changed=0;untouched=[]
 for index,(ta,tb) in enumerate(zip(a,b)):
  assert ta[:4]==tb[:4],'layer changed'
  for j in range(3):assert ta[16+j*16:20+j*16]==tb[16+j*16:20+j*16],'colour changed'
  if ta==tb:untouched.append(ta);continue
  assert cab,'intermediate geometry changed'
  p,q=points(ta),points(tb);sign=-1 if tail else 1
  for j in range(3):
   if np.array_equal(p[j],q[j]):continue
   colour=struct.unpack_from('<I',ta,16+j*16)[0]
   is_seam=colour!=white
   assert p[j,0]*sign>7.9 and (p[j,2]<1.1 or is_seam),(m['id'],index,'outside low chin/seam',p[j])
   assert p[j,1]==q[j,1],'lateral width changed'
   assert (-0.25 if is_seam else -1e-6)<=(q[j,0]-p[j,0])*sign<=0.30 and -1e-6<=q[j,2]-p[j,2]<=0.241
  changed+=1
 if cab:assert changed>0
 else:assert a==b
 assert m['minimum']==next(x for x in a_manifest['models'] if x['id']==m['id'])['minimum']
 assert m['maximum']==next(x for x in a_manifest['models'] if x['id']==m['id'])['maximum']
 rows.append({'id':m['id'],'triangles':len(b),'changed_low_chin_triangles':changed,'unchanged_triangles':len(untouched),'unchanged_payload_sha256':sha(b''.join(untouched)),'all_colours_layers_and_bounds_preserved':True})
def measure(root):
 p=np.concatenate([points(t) for t in read(root/'models/emu3000-ed.m3dmodel') if all(struct.unpack_from('<I',t,16+j*16)[0]==white for j in range(3))])
 p=p[p[:,0]>8];lo=float(p[:,2].min());toe=p[p[:,2]<=lo+0.02];return {'minimum_white_nose_z_m':lo,'lowest_corner_x_m':float(toe[:,0].min()),'horizontal_run_from_tip_m':float(10.675-toe[:,0].min())}
a,b=measure(old),measure(new);assert b['minimum_white_nose_z_m']>a['minimum_white_nose_z_m']+0.20;assert b['horizontal_run_from_tip_m']<a['horizontal_run_from_tip_m']-0.20
(new/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':a_manifest['producer_commit'],'method':'actual52-byte same-index triangles: positions only in low white cab nose and its refitted seam; all triangle counts/colours/layers/bounds and other geometry preserved; virtual model measurements, not engineering dimensions','before':a,'after':b,'models':rows},indent=2)+'\n')
print('VERIFIED12 intermediate payloads identical; only low white chin and its refitted seam vertices move; upper cab, doors, running gear, counts and bounds preserved')
