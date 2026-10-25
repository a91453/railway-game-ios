"""Roof-only revision versus genuine 68913f4f; inspect real native triangle records and sections."""
import sys,json,struct,collections
from pathlib import Path
import numpy as np
old,new=map(Path,sys.argv[1:]);results=[]
def read(path):
 b=path.read_bytes();count,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 raw=[b[start+i*52:start+(i+1)*52] for i in range(count)]
 p=np.array([[struct.unpack_from('<fff',r,4+j*16) for j in range(3)] for r in raw])
 return p,raw

def section(p,z):
 result=[]
 for t in p:
  if z<t[:,2].min()-1e-7 or z>t[:,2].max()+1e-7:continue
  q=[]
  for j in range(3):
   a,b=t[j],t[(j+1)%3];d=b[2]-a[2]
   if abs(d)<1e-9:
    if abs(a[2]-z)<1e-7:q.extend([a,b])
   else:
    u=(z-a[2])/d
    if -1e-7<=u<=1.0000001:q.append(a+(b-a)*u)
  if len(q)>=2:result.append(np.array(q))
 return result

def continuity(p,side):
 intervals=[]
 for q in section(p,4.0):
  q=q[(q[:,1]*side>0.88)&(q[:,1]*side<1.06)&(q[:,0]>-3.50)&(q[:,0]<3.20)]
  if len(q)>=2:intervals.append((q[:,0].min(),q[:,0].max()))
 merged=[]
 for a,b in sorted(intervals):
  if merged and a<=merged[-1][1]+1e-5:merged[-1]=(merged[-1][0],max(b,merged[-1][1]))
  else:merged.append((a,b))
 return max((b-a for a,b in merged),default=0)

def width(p):
 q=p.reshape(-1,3);q=q[(np.abs(q[:,0])<7.30)&(q[:,2]>3.80)]
 return float(np.ptp(q[:,1]))

def height(p):
 q=p.reshape(-1,3);q=q[(q[:,0]>-3.50)&(q[:,0]<3.20)&(q[:,2]>3.60)]
 return float(q[:,2].max())

for id in ['e500','e500-far']:
 a,ar=read(old/'models'/f'{id}.m3dmodel');b,br=read(new/'models'/f'{id}.m3dmodel')
 A=collections.Counter(ar);B=collections.Counter(br)
 np.testing.assert_array_equal(a.min(axis=(0,1)),b.min(axis=(0,1)));np.testing.assert_array_equal(a.max(axis=(0,1)),b.max(axis=(0,1)))
 for diff in [A-B,B-A]:
  for raw in diff:
   p=np.array([struct.unpack_from('<fff',raw,4+j*16) for j in range(3)])
   assert np.all(p[:,2]>=3.60) and np.all(np.abs(p[:,0])<=7.30),('change outside roof-only region',id,p)
 protected=sum(n for r,n in A.items() if not all(struct.unpack_from('<f',r,4+j*16+8)[0]>=3.60 and abs(struct.unpack_from('<f',r,4+j*16)[0])<=7.30 for j in range(3)))
 # Single-arm mechanism above the tray stays byte-identical, including its contact bar.
 # Restrict in X to the collector, so the intentionally lowered central housing is excluded.
 def collector(p,r):return collections.Counter(row for t,row in zip(p,r) if np.all(t[:,0]>4.9) and np.all(t[:,0]<6.9) and np.all(t[:,2]>3.90))
 assert collector(a,ar)==collector(b,br),'collector mechanism changed'
 before=[continuity(a,s) for s in [-1,1]];after=[continuity(b,s) for s in [-1,1]]
 assert min(after)>6.4,('roof enclosure still separated',after)
 aw,bw=width(a),width(b);ah,bh=height(a),height(b)
 assert bw<2.08,('roof platform still too wide',bw)
 assert bh<4.22,('central roof still too tall',bh)
 failures=int(min(before)<=6.4)+int(aw>=2.08)+int(ah>=4.22)
 assert failures==3,('genuine revision2 did not reproduce all three defects',failures,before,aw,ah)
 # Delete actual enclosure faces that bridge its centre: the same continuity criterion must reject it.
 remove=np.all(b[:,:,2]>=3.60,axis=1)&np.all(np.abs(b[:,:,0])<3.50,axis=1)&np.any(b[:,:,0]<-0.4,axis=1)&np.any(b[:,:,0]>0.4,axis=1)
 assert max(continuity(b[~remove],s) for s in [-1,1])<6.4,'deleted casing mutation missed'
 bad=b.copy();mask=(np.abs(bad[:,:,0])<7.30)&(bad[:,:,2]>3.80);bad[:,:,1][mask]*=1.20
 assert width(bad)>2.08,'widened roof mutation missed'
 results.append({'id':id,'unchanged_non_roof_triangle_records':protected,'all_changed_records_within_roi':{'abs_x_max_m':7.30,'z_min_m':3.60},'collector_mechanism_records_unchanged':True,'casing_continuity_before_m':before,'casing_continuity_after_m':after,'upper_roof_frontal_width_before_m':aw,'upper_roof_frontal_width_after_m':bw,'central_roof_top_before_m':ah,'central_roof_top_after_m':bh,'genuine_previous_visible_failures':failures,'deleted_casing_and_widened_roof_mutations_rejected':True})
(new/'roof-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':'68913f4f8c5dd4a681c3ce58140aad3e479c015f','method':'exact 52-byte native triangle record multiset; actual horizontal section intervals and projected geometric bounds','models':results,'limits':'Virtual-model preservation and E500-specific display geometry, not engineering dimensions or calibrated photo similarity.'},indent=2)+'\n')
print('VERIFIED roof-only record changes, protected collector, and six true previous-version visible failures')
