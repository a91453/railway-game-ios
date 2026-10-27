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

# Palette is recorded by the producer's declared color constant, not guessed.
glass=int(manifest['palette']['glass']);tire=int(manifest['palette']['hardware']);records=[]
for m in manifest['models']:
 if m['category']!='section':continue
 p,c=read(root/m['native']);g=np.all(c==glass,axis=1);back=p[~g];normals=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);area=np.linalg.norm(normals,axis=1);normals/=area[:,None]
 cent=p.mean(axis=1); outward=g & (area>.024) & (((np.abs(normals[:,1])>.9)&(normals[:,1]*cent[:,1]>0))|((np.abs(normals[:,0])>.8)&(normals[:,0]*cent[:,0]>0)&(np.abs(cent[:,0])>7.4)&(np.abs(cent[:,1])<1.15)))
 samples=np.flatnonzero(outward); dist=[];blocked=[];origins=[]
 for i in samples:
  o,n=cent[i],normals[i];d=backing_distance(o,back);dist.append(d);origins.append((o,n))
  assert d<=.065,(m['id'],'glass backing',d,o)
  ray=nearest(o+n*.0003,n,back)
  if ray<.5:blocked.append({'face':int(i),'distance':ray,'point':o.tolist()})
 assert len(samples)>0
 assert not blocked,(m['id'],'outward glass obstruction',blocked[:3])
 o,n=next((o,n) for o,n in origins if abs(n[1])>.9)
 assert backing_distance(o+n*.3,back)>.065,'floating glass mutation'
 assert nearest(o-n*.2,n,back)<.2,'buried glass mutation'
 tp=p[np.all(c==tire,axis=1)];wheel=[]
 for ids in components(tp):
  pts=tp[ids].reshape(-1,3);lo=pts.min(0);hi=pts.max(0);size=hi-lo
  if .69<size[0]<.73 and .1<size[1]<.25 and .69<size[2]<.73:
   assert abs(lo[2])<1e-5 and abs(size[2]-.710)<1e-5,(m['id'],'tread/radius')
   o=(lo+hi)/2;o[2]=hi[2]
   mask=np.ones(len(tp),bool);mask[ids]=False
   d=min(nearest(o,np.array([0.,0.,1.]),p[~np.all(c==tire,axis=1)]),nearest(o,np.array([0.,0.,1.]),tp[mask]))
   assert .005<=d<.35,(m['id'],'wheel top',d)
   raised=pts+np.array([0,0,.25]);assert abs(raised.min(0)[2])>1e-5
   wheel.append({'minimum':lo.tolist(),'maximum':hi.tolist(),'up_ray_clearance_m':d})
 assert len(wheel)==8,(m['id'],'wheel components',len(wheel))
 # Actual connected roof and collector groups tested against rest triangles.
 groups=components(p);supports=[]
 for ids in groups:
  pts=p[ids].reshape(-1,3);lo=pts.min(0);hi=pts.max(0)
  roof=lo[2]>=3.419
  collector=hi[2]<1.05 and max(abs(lo[1]),abs(hi[1]))>1.15
  if not(roof or collector):continue
  rest=np.delete(p,ids,0);pts=np.concatenate((np.unique(pts,axis=0),p[ids].mean(1)));pts=pts[np.linspace(0,len(pts)-1,min(40,len(pts)),dtype=int)]
  ds=[backing_distance(o,rest) for o in pts]
  assert min(ds)<=.065,(m['id'],'floating equipment',lo,hi,min(ds))
  if roof and hi[0]-lo[0]>3:
   shifted=pts+np.array([0,0,.70]);assert min(backing_distance(o,rest) for o in shifted)>.065,'float housing mutation'
  supports.append({'kind':'roof' if roof else 'collector','minimum':lo.tolist(),'maximum':hi.tolist(),'samples':len(pts),'minimum_distance_m':min(ds)})
 records.append({'id':m['id'],'glass_outward_samples':len(samples),'max_backing_m':max(dist),'glass_samples':[{'origin':o.tolist(),'direction':n.tolist(),'backing_distance_m':d} for (o,n),d in zip(origins,dist)],'outward_obstructions':blocked,'wheels':wheel,'equipment_support_samples':supports,'glass_buried_floating_wheel_raised_roof_float_mutations_rejected':True})
(root/'support-verification.json').write_text(json.dumps({'platform':'Linux Python NumPy independent triangle reader','models':records,'method':'all outward glazing faces with double-area >0.024 m2; outward normal rays start 0.3mm; opaque backing <=65mm; actual connected rubber wheel components; wheel-top +Z ray; roof/collector contact minimum over <=40 actual vertices/face centres,65mm tolerance','limits':'sampled static contacts, no complete support/collision graph or suspension dynamics'},indent=2))
print('VERIFIED glass/wheel/equipment',len(records))
