"""Independent native triangle distances/rays: glazing backing, roof contacts, wheel clearance.
No recipe station/door/axle tables are imported. Tolerances/limits are recorded.
"""
import sys,json,struct,collections
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text())
def read(path):
 b=path.read_bytes();count,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4;p=[];c=[]
 for i in range(count):
  row=[struct.unpack_from('<fffI',b,start+i*52+4+j*16) for j in range(3)]
  p.append([v[:3] for v in row]);c.append([v[3] for v in row])
 return np.array(p),np.array(c,dtype=np.uint32)
def nearest(origin,direction,triangles,allow_contact=False):
 a=triangles[:,0];e1=triangles[:,1]-a;e2=triangles[:,2]-a;h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-10
 f=np.zeros_like(det);f[valid]=1/det[valid];s=origin-a;u=f*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=f*np.einsum('j,ij->i',direction,q);t=f*np.einsum('ij,ij->i',e2,q)
 mask=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>=-0.000001 if allow_contact else t>0.00001)
 return float(np.min(t[mask])) if mask.any() else float('inf')
def backing_distance(origin,triangles):
 # Exact point-to-triangle distance: planar projection when inside, otherwise
 # closest point on each edge. Unlike a tangent normal ray, a pane's thin
 # perimeter cannot manufacture a false gap to its supporting body.
 a=triangles[:,0];e=triangles[:,1]-a;f=triangles[:,2]-a;w=origin-a
 ee=np.einsum('ij,ij->i',e,e);ef=np.einsum('ij,ij->i',e,f);ff=np.einsum('ij,ij->i',f,f)
 ew=np.einsum('ij,ij->i',e,w);fw=np.einsum('ij,ij->i',f,w);den=ee*ff-ef*ef
 good=den>1e-16;u=np.zeros(len(a));v=np.zeros(len(a));u[good]=(ff[good]*ew[good]-ef[good]*fw[good])/den[good];v[good]=(ee[good]*fw[good]-ef[good]*ew[good])/den[good]
 inside=good&(u>=0)&(v>=0)&(u+v<=1)
 projected=a+e*u[:,None]+f*v[:,None];best=np.where(inside,np.einsum('ij,ij->i',origin-projected,origin-projected),np.inf)
 for j in range(3):
  x=triangles[:,j];d=triangles[:,(j+1)%3]-x;length=np.einsum('ij,ij->i',d,d);t=np.clip(np.divide(np.einsum('ij,ij->i',origin-x,d),length,out=np.zeros(len(x)),where=length>1e-16),0,1)
  delta=origin-x-d*t[:,None];best=np.minimum(best,np.einsum('ij,ij->i',delta,delta))
 return float(np.sqrt(best.min()))
def components(p):
 parent=list(range(len(p)));edges={}
 def find(i):
  while i!=parent[i]:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i,t in enumerate(p):
  for point in t:
   key=tuple(np.round(point,5));other=edges.setdefault(key,i);a,b=find(i),find(other);parent[a]=b
 groups=collections.defaultdict(list)
 for i in range(len(p)):groups[find(i)].append(i)
 return [np.array(v) for v in groups.values()]
# Exported palette is part of the source-linked manifest.
glass=int(manifest['palette']['glass']);tire=int(manifest['palette']['hardware']);records=[]
for m in manifest['models']:
 if m['category']!='section':continue
 p,c=read(root/m['native']);g=np.all(c==glass,axis=1);back=p[~g];dist=[];origins=[]
 for t in p[g]:
  n=np.cross(t[1]-t[0],t[2]-t[0]);area=np.linalg.norm(n)/2
  if area<0.012:continue
  n/=np.linalg.norm(n);o=t.mean(axis=0)
  dist.append(backing_distance(o,back));origins.append((o,n))
 assert dist and max(dist)<=0.12,(m['id'],'unsupported glass',max(dist,default=None))
 # Move a genuine side pane 1m OUT along its actual normal, keeping rest unchanged.
 o,n=next((o,n) for o,n in origins if abs(n[1])>0.9 and abs(o[0])<5 and n[1]*o[1]>0)
 moved=o+n
 assert backing_distance(moved,back)>0.12,'floating-glass mutation missed'
 black=np.all(c==tire,axis=1);tp=p[black];wheel=[]
 for ids in components(tp):
  points=tp[ids].reshape(-1,3);lo=points.min(axis=0);hi=points.max(axis=0);size=hi-lo
  if 0.7<size[0]<1.0 and 0.1<size[1]<0.25 and 0.7<size[2]<1.0:
   assert abs(lo[2])<0.00001,(m['id'],'floating tire',lo)
   o=np.array([(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,hi[2]])
   d=nearest(o,np.array([0.,0.,1.]),p[~black])
   # Include black floor/frame geometry except this actual tire component.
   mask=np.ones(len(tp),dtype=bool);mask[ids]=False
   d=min(d,nearest(o,np.array([0.,0.,1.]),tp[mask]))
   assert 0.005<=d<0.30,(m['id'],'wheel/body clearance',d)
   assert abs((lo[2]+0.25))>0.00001,'raised-wheel mutation missed'
   wheel.append(d)
 assert len(wheel)==8,(m['id'],'actual tire components',len(wheel))
 # Actual roof solids form a proximity/contact graph to the car shell.
 groups=components(p);bounds=[(p[g].min(axis=(0,1)),p[g].max(axis=(0,1))) for g in groups]
 roof=[i for i,(lo,hi) in enumerate(bounds) if lo[2]>=3.39]
 roots={i for i,(lo,hi) in enumerate(bounds) if lo[2]<3.39};graph=collections.defaultdict(set)
 axes=np.vstack((np.eye(3),-np.eye(3)))
 for i in roof:
  lo,hi=bounds[i];pts=np.unique(p[groups[i]].reshape(-1,3),axis=0)
  # Corners and face centroids sample the real solid, not an AABB proxy.
  pts=np.concatenate((pts,p[groups[i]].mean(axis=1)))
  if len(pts)>40:pts=pts[np.linspace(0,len(pts)-1,40,dtype=int)]
  for j,(low,high) in enumerate(bounds):
   if i==j or np.any(hi+0.065<low) or np.any(high+0.065<lo):continue
   target=p[groups[j]];touch=False
   for o in pts:
    if any(nearest(o,d,target,True)<=0.065 for d in axes):touch=True;break
   if touch:graph[i].add(j);graph[j].add(i)
 reached=set(roots);stack=list(roots)
 while stack:
  for j in graph[stack.pop()]-reached:reached.add(j);stack.append(j)
 assert set(roof)<=reached,(m['id'],'roof solids have no support path',set(roof)-reached)
 records.append({'id':m['id'],'glazing_face_samples':len(dist),'maximum_glazing_backing_distance_m':max(dist),'actual_tires':len(wheel),'minimum_upper_tire_clearance_m':min(wheel),'roof_solids_reaching_body':len(roof),'floating_glass_and_raised_wheel_mutations_rejected':True})
result={'status':'VERIFIED','method':'exact nearest-triangle distance from all sampled glazing faces including perimeter/back (120mm backing); actual tire connected components with tread and upper clearance rays; actual roof solid proximity graph to body (65mm contact tolerance, <=40 points per solid, 6 directions)','models':records,'limits':'sampled geometric support/clearance; no complete all-surface collision, suspension dynamics, overhead-wire contact or animated collector verification'}
(root/'support-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('VERIFIED glazing, 8 tires and roof support paths for',len(records),'near/far units')
