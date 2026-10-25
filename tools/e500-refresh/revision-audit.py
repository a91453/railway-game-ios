"""Actual triangle preservation and visible revision regressions; no recipe tables imported."""
import collections,json,struct,sys
from pathlib import Path
import numpy as np
old,new=map(Path,sys.argv[1:]);rows=[]
def read(file):
 b=file.read_bytes();count,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 records=[struct.unpack_from('<fffI',b,start+i*52+4+j*16) for i in range(count) for j in range(3)]
 p=np.array([r[:3] for r in records]).reshape(-1,3,3);c=np.array([r[3] for r in records],dtype=np.uint32).reshape(-1,3)
 return p,c

def components(p):
 parent=list(range(len(p)));keys={}
 def root(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i,t in enumerate(p):
  for q in t:
   k=tuple(np.round(q,5));j=keys.setdefault(k,i);parent[root(i)]=root(j)
 groups=collections.defaultdict(list)
 for i in range(len(p)):groups[root(i)].append(i)
 return list(groups.values())

def triangles(p,c):
 # Preserve winding while ignoring the arbitrary starting corner.
 out=collections.Counter()
 for t,cols in zip(p,c):
  v=[tuple(np.round(q,6))+(int(color),) for q,color in zip(t,cols)]
  out[min(tuple(v[i:]+v[:i]) for i in range(3))]+=1
 return out

def slice_points(p,axis,at):
 out=[]
 for t in p:
  low=t[:,axis].min();high=t[:,axis].max()
  if at<low-1e-7 or at>high+1e-7:continue
  for j in range(3):
   a,b=t[j],t[(j+1)%3];d=b[axis]-a[axis]
   if abs(d)<1e-9:
    if abs(a[axis]-at)<1e-7:out.extend([a,b])
   else:
    u=(at-a[axis])/d
    if -1e-7<=u<=1.0000001:out.append(a+(b-a)*u)
 return np.array(out)

def shell(p):
 for ids in components(p):
  q=p[ids];low=q.min(axis=(0,1));high=q.max(axis=(0,1))
  if high[0]-low[0]>19 and abs(low[2]-1.15)<1e-5 and abs(high[2]-3.75)<1e-5:return q
 raise AssertionError('actual body shell not found')

def continuity(p,side,end):
 # Horizontal slice of the actual outboard bogie frame; project connected x intervals.
 intervals=[]
 for t in p:
  q=slice_points(np.array([t]),2,0.84)
  if len(q)<2:continue
  q=q[(q[:,1]*side>=0.99)&(q[:,1]*side<=1.23)&(q[:,0]*end>3.5)&(q[:,0]*end<8.6)]
  if len(q)>=2:intervals.append((q[:,0].min(),q[:,0].max()))
 intervals.sort();merged=[]
 for a,b in intervals:
  if merged and a<=merged[-1][1]+1e-4:merged[-1]=(merged[-1][0],max(b,merged[-1][1]))
  else:merged.append((a,b))
 return max((b-a for a,b in merged),default=0)

def upper_arm(p):
 q=slice_points(p,2,5.10);return float(np.ptp(q[:,1]))

manifest=json.loads((new/'manifest.json').read_text());palette=manifest['palette'];tire=int(palette['tire']);body=int(palette['body'])
for id in ['e500','e500-far']:
 a,ac=read(old/'models'/f'{id}.m3dmodel');b,bc=read(new/'models'/f'{id}.m3dmodel')
 assert triangles(a[np.all(ac==tire,axis=1)],ac[np.all(ac==tire,axis=1)])==triangles(b[np.all(bc==tire,axis=1)],bc[np.all(bc==tire,axis=1)]),'actual tyre triangles changed'
 def panel(p,c):return np.all(np.abs(p[:,:,0])<=7.326,axis=1)&np.all(np.abs(p[:,:,1])>=1.37,axis=1)&np.all(c==body,axis=1)
 A=panel(a,ac);B=panel(b,bc);assert A.any() and triangles(a[A],ac[A])==triangles(b[B],bc[B]),'protected machine-room panels changed'
 np.testing.assert_allclose(a.min(axis=(0,1))[:2],b.min(axis=(0,1))[:2],atol=1e-5)
 np.testing.assert_allclose(a.max(axis=(0,1))[:2],b.max(axis=(0,1))[:2],atol=1e-5)
 sa,sb=shell(a),shell(b);error=0
 for x in np.linspace(-9.98,9.98,201):
  qa,qb=slice_points(sa,0,x),slice_points(sb,0,x)
  assert len(qa) and len(qb)
  error=max(error,abs(qa[:,2].min()-qb[:,2].min()),abs(qa[:,2].max()-qb[:,2].max()))
 assert error<0.00002,('protected longitudinal silhouette changed',error)
 old_fail=0;frame=[]
 for side in [-1,1]:
  for end in [-1,1]:
   before,after=continuity(a,side,end),continuity(b,side,end);assert after>4.0,('bogie side frame discontinuous',after)
   old_fail+=int(before<=4.0);frame.append({'side':side,'end':end,'before_m':before,'after_m':after})
 before,after=upper_arm(a),upper_arm(b);assert after<0.1,('A-frame upper collector',after);old_fail+=int(before>=0.1)
 assert old_fail==5,('genuine revision-1 visible regressions did not fail',old_fail)
 # Remove the actual right-hand outboard frame region; the same continuity check must reject it.
 mask=~np.all((b[:,:,1]>0.99)&(b[:,:,1]<1.23)&(b[:,:,0]>3.5)&(b[:,:,0]<8.6),axis=1)
 assert continuity(b[mask],1,1)<4.0,'deleted frame mutation missed'
 rows.append({'id':id,'protected_tyre_triangles':int(np.sum(np.all(ac==tire,axis=1))),'protected_side_panel_triangles':int(A.sum()),'longitudinal_slices':201,'maximum_shell_profile_difference_m':error,'actual_outboard_frame_lengths':frame,'upper_arm_front_width_before_m':before,'upper_arm_front_width_after_m':after,'genuine_previous_failures':old_fail,'deleted_actual_frame_mutation_rejected':True})
(new/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':'8127c765f8c07570de17b813b6329b93d9871a68','models':rows,'limits':'Preserves measured shell side-envelope and selected actual tyre/panel triangles, not all body vertices or all projected pixels. Regression thresholds apply to this E500 only.'},indent=2)+'\n')
print('VERIFIED protected real tyres/panels and 201 shell slices; genuine prior version fails 10 visible checks')
