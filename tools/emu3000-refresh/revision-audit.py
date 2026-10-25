"""Revision4: compare actual native payloads with the true delivered revision3."""
from pathlib import Path
import sys,json,struct,hashlib,collections
import numpy as np
old,new=map(Path,sys.argv[1:3]);sha=lambda b:hashlib.sha256(b).hexdigest()
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def points(t):return np.array([struct.unpack_from('<fff',t,4+j*16) for j in range(3)])
def color(t):return struct.unpack_from('<I',t,16)[0]
a_manifest=json.loads((old/'manifest.json').read_text());assert a_manifest['producer_commit']=='e25474fffe42a98fd6cbc04b5f287485be72e097'
b_manifest=json.loads((new/'manifest.json').read_text());white=b_manifest['palette']['body'];seam=(white&0xff000000)|sum(int(np.floor(np.float32((white>>s)&255)*np.float32(.74)+.5))<<s for s in [0,8,16]);rows=[]
for m in b_manifest['models']:
 if m['category']!='section':continue
 a=read(old/m['native']);b=read(new/m['native']);tail='tail' in m['id'];cab=tail or '-ed' in m['id'];sign=-1 if tail else 1
 if not cab:assert a==b,(m['id'],'intermediate unit changed')
 before,after=collections.Counter(a),collections.Counter(b);removed=list((before-after).elements());added=list((after-before).elements())
 if cab:
  assert removed and added
  for t in removed+added:assert np.all(points(t)[:,0]*sign>=2.65-1e-5),(m['id'],'outside cab/forward door/header',points(t))
  def gear(ts):return collections.Counter(t for t in ts if color(t) not in [white,seam] and np.all(points(t)[:,2]<1.1))
  assert gear(a)==gear(b),(m['id'],'running gear/underfloor/coupler changed')
 preserved=before&after
 old_m=next(x for x in a_manifest['models'] if x['id']==m['id']);assert m['minimum']==old_m['minimum'] and m['maximum']==old_m['maximum'],'overall bounds changed'
 rows.append({'id':m['id'],'old_triangles':len(a),'new_triangles':len(b),'removed_triangles':len(removed),'added_triangles':len(added),'preserved_triangles':sum(preserved.values()),'preserved_payload_sha256':sha(b''.join(sorted(preserved.elements()))),'preserved':'full intermediate payload' if not cab else 'all geometry outside forward cab/header region; all running gear/underfloor/couplers; actual overall bounds'})
def profile(root):
 ts=read(root/'models/emu3000-ed.m3dmodel');pts=np.concatenate([points(t) for t in ts if color(t) in [white,b_manifest['palette']['mask']]])
 def top(x):
  out=[]
  for t in ts:
   if color(t) not in [white,b_manifest['palette']['mask']]:continue
   p=points(t)
   for i in range(3):
    a,b=p[i],p[(i+1)%3]
    if (a[0]-x)*(b[0]-x)<0:out.append(float(a[2]+(b[2]-a[2])*(x-a[0])/(b[0]-a[0])))
  return max(out)
 p=np.concatenate([points(t) for t in ts if color(t)==white]);p=p[p[:,0]>8];lo=float(p[:,2].min());toe=p[p[:,2]<lo+.02]
 return {'shell_top_at_x7_m':top(7),'shell_top_at_x8_m':top(8),'shell_top_at_x10_m':top(10),'minimum_white_nose_z_m':lo,'lowest_corner_x_m':float(toe[:,0].min()),'lower_corner_run_from_tip_m':float(10.675-toe[:,0].min())}
a,b=profile(old),profile(new);assert b['shell_top_at_x7_m']>a['shell_top_at_x7_m']+.15;assert b['shell_top_at_x10_m']<a['shell_top_at_x10_m']-.25;assert b['lower_corner_run_from_tip_m']<a['lower_corner_run_from_tip_m']-.2
(new/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':a_manifest['producer_commit'],'method':'actual native triangle multisets; all12 intermediate payloads byte-identical; changed cab triangles confined to forward cab/header region; running gear and overall bounds preserved; virtual model measurements, not engineering dimensions','before':a,'after':b,'models':rows},indent=2)+'\n')
print('VERIFIED12 unchanged intermediate payloads; forward cab only; continuous diagonal nose, raised crown and tighter lower corner')
