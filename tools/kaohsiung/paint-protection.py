"""Actual paint-only native surface coverage and accepted-side protection.
BEFORE AFTER BEFORE_SHELL AFTER_SHELL; shell inputs are true shellOnly exports.
Coordinates are Float32 display samples, not engineering tolerances.
"""
from pathlib import Path
from collections import Counter,defaultdict
import json,sys,struct
import numpy as np
from audit import read

EPS=3e-5

def bow(t,far):
 h=t[:,:,2];w=abs(t[:,:,1])
 lateral=np.interp(w,[0,1.02,1.575] if far else [0,.55,1.02,1.34,1.575],[0,-.07,-.34] if far else [0,-.016,-.07,-.17,-.34])
 return 10.7325+lateral+np.interp(h,[.78,1.18,1.95,3.26,3.6],[-.12,-.04,0,-.16,-.34])

def signature(t,f,selected,c=None):
 return Counter((tuple(np.round(q.flatten()*1e5).astype(int)),int(flag),int(color)) for q,flag,color in zip(t[selected],f[selected],c[selected] if c is not None else np.zeros(selected.sum(),dtype=int)))

def native_signature(path,selected):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 assert n==len(selected)
 return Counter(b[o+i*52:o+(i+1)*52] for i in np.flatnonzero(selected))

def cross2(a,b):return a[0]*b[1]-a[1]*b[0]

def area(p):
 return abs(sum(cross2(p[(i+1)%len(p)]-p[0],p[i]-p[0]) for i in range(len(p)))/2) if len(p)>2 else 0.

def intersection(a,b):
 p=list(a);sign=1 if cross2(b[1]-b[0],b[2]-b[0])>=0 else -1
 for i in range(3):
  u,v=b[i],b[(i+1)%3];out=[]
  for j in range(len(p)):
   x,y=p[j],p[(j+1)%len(p)];dx=sign*cross2(v-u,x-u);dy=sign*cross2(v-u,y-u)
   if dx>=-1e-10:out.append(x)
   if (dx>=0)!=(dy>=0):out.append(x+(y-x)*dx/(dx-dy))
  p=out
  if len(p)<3:return 0.
 return area(p)

def front_cells(t,far):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);n/=np.linalg.norm(n,axis=1)[:,None]
 sel=(abs(t[:,:,0]-bow(t,far))<EPS).all(axis=1)&(n[:,0]>.6)
 p=t[sel][:,:,[1,2]];p[:,:,0]*=-1
 ws=np.array([-1.575,-1.02,0,1.02,1.575] if far else [-1.575,-1.34,-1.02,-.55,0,.55,1.02,1.34,1.575]);hs=np.array([.78,1.18,1.95,3.26,3.6]);cells=defaultdict(list)
 for tri in p:
  c=tri.mean(axis=0);i=min(len(ws)-2,max(0,np.searchsorted(ws,c[0],side='right')-1));j=min(len(hs)-2,max(0,np.searchsorted(hs,c[1],side='right')-1))
  assert tri[:,0].min()>=ws[i]-EPS and tri[:,0].max()<=ws[i+1]+EPS
  assert tri[:,1].min()>=hs[j]-EPS and tri[:,1].max()<=hs[j+1]+EPS
  cells[(int(i),int(j))].append(tri)
 return cells

def coverage(a,b):
 assert a.keys()==b.keys(),'front plane cells changed'
 maximum=0.;total=0.
 for key,aa in a.items():
  bb=b[key]
  for left,right in [(aa,bb),(bb,aa)]:
   low=np.array([p.min(axis=0) for p in right]);high=np.array([p.max(axis=0) for p in right])
   for tri in left:
    candidates=np.flatnonzero((high>=tri.min(axis=0)-EPS).all(axis=1)&(low<=tri.max(axis=0)+EPS).all(axis=1))
    expected=area(tri);got=sum(intersection(tri,right[i]) for i in candidates);err=abs(got-expected);maximum=max(maximum,err)
    assert err<1e-7+expected*2e-4,('front shell coverage changed',key,expected,got)
  total+=sum(area(t) for t in aa)
 return {'projected_front_area_m2':total,'max_triangle_coverage_residual_m2':maximum,'coplanar_bow_tolerance_m':EPS}

before,after,before_shell,after_shell=map(Path,sys.argv[1:5]);m=json.loads((after/'manifest.json').read_text());rows=[]
for r in m['models']:
 if r.get('native_kind')=='assembly':continue
 old,of=read(before/r['native']);new,nf=read(after/r['native']);far=r['id'].endswith('-far');trailer='-t' in r['id']
 assert native_signature(before/r['native'],(old[:,:,0]<=9).all(axis=1))==native_signature(after/r['native'],(new[:,:,0]<=9).all(axis=1)),'accepted body colours/geometry changed'
 if trailer:
  assert (before/r['native']).read_bytes()==(after/r['native']).read_bytes(),'T changed'
  row={'id':r['id'],'trailer_full_bytes_equal':True}
 else:
  def outside(t):
   offset=t[:,:,0]-bow(t,far)
   return ((offset<-0.12-EPS)|(offset>EPS)).any(axis=1)
  assert signature(old,of,outside(old))==signature(new,nf,outside(new)),'hardware/outside-shell geometry changed'
  so,_=read(before_shell/('models/'+r['id']+'-shell.m3dmodel'));sn,_=read(after_shell/('models/'+r['id']+'-shell.m3dmodel'))
  row={'id':r['id'],'outside_front_paint_slab_geometry_flags_equal':True,'front_shell':coverage(front_cells(so,far),front_cells(sn,far))}
 row['accepted_straight_side_full_native_vertex_fields_equal']=True;rows.append(row)
report={'status':'VERIFIED','true_previous_producer':'3874b4259a99bd7b4f7e42f1b94fa23a34d4cf2c','accepted_side_producer':'3874b4259a99bd7b4f7e42f1b94fa23a34d4cf2c','models':rows,'limits':'Exact sampled triangle intersection coverage on the same piecewise-planar bow; Float32/clip tolerance stated. Internal paint partitions may differ. Frontal paint projects into nose/oblique views; no claim that every side-camera nose pixel or adjacent baked shade is unchanged.'}
(after/'paint-protection.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
