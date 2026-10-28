"""C381 revision guards and front-ray checks on actual delivered native meshes.
Photo-derived proportions are review constraints, not engineering dimensions.
"""
import collections, hashlib, json, struct, sys
from pathlib import Path
import numpy as np
old,root=map(Path,sys.argv[1:])
def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 t=np.array([[struct.unpack_from('<fff',b,start+i*52+4+j*16) for j in range(3)] for i in range(n)])
 c=np.array([struct.unpack_from('<I',b,start+i*52+16)[0] for i in range(n)])
 return t,c
locked=[]
for p in (old/'models').iterdir():
 if p.name.startswith(('c371-','emu3000-')):
  assert p.read_bytes()==(root/'models'/p.name).read_bytes(),p.name
  locked.append(p.name)
for p in (old/'verification').glob('c371*'):
 assert p.read_bytes()==(root/'verification'/p.name).read_bytes(),p.name
 locked.append('verification/'+p.name)
def geometry(t):return collections.Counter(tuple(np.round(x,5).flat) for x in t)
changes=[]
for name in ['c381-dm','c381-t','c381-m']:
 a,_=read(old/'models'/f'{name}.m3dmodel');b,_=read(root/'models'/f'{name}.m3dmodel')
 ca,cb=geometry(a),geometry(b)
 # Every original roof fitting and running-gear triangle survives unchanged.
 for label,predicate in [('roof',lambda t:(t[:,:,2]>=3.20).all(axis=1)&(t[:,:,0].min(axis=1)<10.50)),('running_gear',lambda t:(t[:,:,2]<.92).all(axis=1)&(abs(t[:,:,0])<10.50).all(axis=1))]:
  assert not geometry(a[predicate(a)])-cb,(name,label)
 changes.append({'id':name,'original_position_triangles_retained':sum((ca&cb).values()),'original_triangles':len(a),'final_triangles':len(b),'original_roof_and_running_gear_positions_retained':True})
t,colors=read(root/'models/c381-dm.m3dmodel');n=len(t)
def visible(tri,y,z):
 a=tri[:,0,1:];u=tri[:,1,1:]-a;v=tri[:,2,1:]-a;q=np.array([y,z])-a
 det=u[:,0]*v[:,1]-u[:,1]*v[:,0];ok=abs(det)>1e-10
 f=np.divide(q[:,0]*v[:,1]-q[:,1]*v[:,0],det,out=np.zeros(n),where=ok)
 g=np.divide(u[:,0]*q[:,1]-u[:,1]*q[:,0],det,out=np.zeros(n),where=ok)
 hits=ok&(f>=-1e-6)&(g>=-1e-6)&(f+g<=1.000001)
 xs=tri[:,0,0]+f*(tri[:,1,0]-tri[:,0,0])+g*(tri[:,2,0]-tri[:,0,0]);xs[~hits]=-np.inf
 i=int(xs.argmax());assert xs[i]>11.45;return int(colors[i])
mask=visible(t,.56,2.6);glass=visible(t,0,2.6);blue=visible(t,0,1.16)
assert len({mask,glass,blue})==3
mask_samples=[(s*y,z) for s in [-1,1] for y in [.56,1.41] for z in [2.3,2.6,2.85]]
glass_samples=[(y,z) for y in [-.25,0,.25] for z in [2.2,2.5,2.8,3.0]]+[(s*y,z) for s in [-1,1] for y in [.78,1.10] for z in [2.65,2.80,2.86]]
def check(tri):
 assert all(visible(tri,y,z)==mask for y,z in mask_samples),'mask backing exposed'
 assert all(visible(tri,y,z)==glass for y,z in glass_samples),'glass hidden by backing'
check(t)
broken=t.copy();broken[(colors==glass)&(t[:,:,0].min(axis=1)>11.45),:,0]-=.30
try:check(broken)
except AssertionError:pass
else:raise AssertionError('buried glass fault accepted')
ys=np.linspace(-1.50,1.50,601);isglass=[visible(t,float(y),2.65)==glass for y in ys]
runs=[]
for i,v in enumerate(isglass):
 if v and (i==0 or not isglass[i-1]):start=i
 if v and (i==len(ys)-1 or not isglass[i+1]):runs.append(float(ys[i]-ys[start]+.005))
assert len(runs)==3 and runs[1]>max(runs[0],runs[2])*1.05,runs
def band_thickness(y):
 zs=np.arange(1.13,1.801,.002);hits=[i for i,z in enumerate(zs) if visible(t,y,float(z))==blue];assert hits
 end=hits[-1];start=end
 while start-1 in hits:start-=1
 return float(zs[end]-zs[start]+.002)
tip,wing=band_thickness(0),band_thickness(.50);assert tip<wing*.45,(tip,wing)
parent=list(range(n));owners={}
def find(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
for i,tri in enumerate(t):
 for v in tri:
  key=tuple(np.round(v,5))
  if key in owners:parent[find(i)]=find(owners[key])
  else:owners[key]=i
components={}
for i in range(n):components.setdefault(find(i),[]).append(i)
boxes=[]
for indices in components.values():
 v=t[indices].reshape(-1,3);lo=v.min(axis=0);hi=v.max(axis=0)
 if len(indices)==12 and all(len(np.unique(np.round(v[:,k],5)))==2 for k in range(3)):boxes.append((indices,lo,hi))
floors=[x for x in boxes if x[2][0]-x[1][0]>23 and abs(x[1][2]-.92)<1e-4 and abs(x[2][2]-1.04)<1e-4];assert len(floors)==1
supports=[x for x in boxes if 11.40<x[1][0]<11.41 and 11.62<x[2][0]<11.63 and abs(x[1][2]-.70)<1e-4 and abs((x[1][1]+x[2][1])/2)>.9];assert len(supports)==2,len(supports)
def contact(a,b):return bool((np.minimum(a[2],b[2])-np.maximum(a[1],b[1])>1e-5).all())
for support in supports:
 assert contact(support,floors[0]),'support does not meet floor'
 damaged=t[support[0]].copy();damaged[:,:,2]-=.05;v=damaged.reshape(-1,3)
 assert not contact((support[0],v.min(axis=0),v.max(axis=0)),floors[0]),'lowered support accepted'
report={'status':'VERIFIED','locked_files_byte_identical':locked,'c381_position_guards':changes,'local_supports':{'actual_box_shells':2,'positive_floor_overlap':True,'lowered_support_50mm_rejected':True,'limits':'Floor/bracket contact only; curved apron and full structural connections are not exhaustively tested.'},'front_ray_samples':{'mask':len(mask_samples),'glass':len(glass_samples),'buried_glass_300mm_rejected':True,'glass_widths_at_2_65m':runs,'blue_tip_and_wing_thickness_m':[tip,wing]},'limits':['sampled orthographic front regions only','original roof and running gear positions retained; hidden equipment not newly verified','no exhaustive collisions, structural analysis, real-device or performance claim']}
(root/'c381-revision-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
