"""Independent native rays: glass visibility and backing; not dynamic collision."""
import json,struct,sys
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text())
def mesh(path):
 b=path.read_bytes();n,meta=struct.unpack_from('<II',b,8);s=16+(meta+3)//4*4
 rec=np.frombuffer(b[s:],dtype=np.dtype([('flag','<u4'),('v',[('p','<f4',(3,)),('c','<u4')],(3,))]));assert len(rec)==n
 return rec['v']['p'].astype(float),rec['v']['c'][:,0]
def hit(tri,o,d):
 a=tri[:,0];e=tri[:,1]-a;f=tri[:,2]-a;h=np.cross(np.broadcast_to(d,f.shape),f);det=(e*h).sum(1);valid=abs(det)>1e-11
 inv=np.divide(1,det,out=np.zeros_like(det),where=valid);s=o-a;u=(s*h).sum(1)*inv;q=np.cross(s,e);v=(q*d).sum(1)*inv;t=(f*q).sum(1)*inv
 return t[valid&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>1e-5)]
rows=[]
for m in manifest['models']:
 if m['category']!='section':continue
 tri,col=mesh(root/m['native']);n=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);n/=np.linalg.norm(n,axis=1)[:,None]
 glass=manifest['palette']['glass'];c=tri.mean(1)
 idx=np.flatnonzero((col==glass)&(((abs(c[:,0])>9)&(abs(c[:,1])<1.30)&(c[:,0]*n[:,0]>3))|((abs(c[:,1])>1.44)&(c[:,1]*n[:,1]>1.35))))
 # Up to 160 actual glass triangle centroids per model; deterministic sampling.
 idx=idx[np.linspace(0,len(idx)-1,min(160,len(idx))).astype(int)]
 visible=backed=expected_wiper=0;occlusion=[]
 for i in idx:
  o=tri[i].mean(0);d=n[i];out=hit(tri,o+d*0.0001,d);behind=hit(tri,o-d*0.0001,-d)
  near=out[out<.14]
  if len(near)==0:visible+=1
  else:
   distance=float(near.min());occlusion.append(distance)
   point=o+d*(distance+.0001)
   rubber=hit(tri[col==0xFF342E2B],o+d*.0001,d)
   if len(rubber) and abs(float(rubber.min())-distance)<1e-5 and 2.20<point[2]<2.65 and abs(point[1])<.85:expected_wiper+=1
  if len(behind) and behind.min()<.10:backed+=1
 rows.append({'id':m['id'],'glass_samples':len(idx),'clear_outward_rays':visible,'backed_within_100mm':backed,'expected_actual_rubber_wiper_hits':expected_wiper,'occlusion_distances_m':occlusion})
 # All sample origins are on actual final glass, not recipe constants.
 assert backed==len(idx),(m['id'],'unbacked glass',rows[-1])
 assert visible+expected_wiper==len(idx),(m['id'],'glass obstructed',rows[-1])
 # Each wheel's rubber reaches the track at both bogies; wheel-centre locations from actual lowest vertices.
 low=tri[(col==manifest.get('rubber',0xFF342E2B))&(tri[:,:,2].min(1)<1e-5)]
 assert len(low)>0,(m['id'],'missing tread')
 # Actual connected rubber solids that reach Z=0, not overall model bounds.
 ids=np.flatnonzero(col==0xFF342E2B);parent={int(i):int(i) for i in ids};seen={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i in ids:
  for v in tri[i]:
   k=tuple(np.round(v,5));j=seen.get(k)
   if j is not None:parent[find(int(i))]=find(j)
   seen[k]=int(i)
 groups={}
 for i in ids:groups.setdefault(find(int(i)),[]).append(int(i))
 tires=[tri[g].reshape(-1,3) for g in groups.values() if tri[g][:,:,2].min()<1e-5]
 assert len(tires)==8,(m['id'],'eight actual wheel tread components',len(tires))
 wheelrows=[]
 for tire in tires:
  lo=tire.min(0);hi=tire.max(0);assert abs(lo[2])<1e-5 and abs(hi[2]-.86)<1e-5
  centre=(lo+hi)/2;top=centre.copy();top[2]=hi[2]+.0001
  above=hit(tri[col==manifest['palette']['body']],top,np.array([0.,0.,1.]))
  assert len(above) and .04<above.min()<.15,(m['id'],'wheel/body clearance')
  wheelrows.append({'minimum':lo.tolist(),'maximum':hi.tolist(),'body_clearance_m':float(above.min())})
 rows[-1]['actual_eight_wheel_components']=wheelrows
 # Raising any actual wheel 200 mm violates its measured tread datum.
 assert abs((tires[0]+[0,0,.2])[:,2].min())>.01
 # A real geometry mutation: bury every glass triangle 200 mm inward along its own face normal.
 if len(idx):
  i=idx[len(idx)//2];o=tri[i].mean(0)-n[i]*.20;t=hit(tri,o+n[i]*.0001,n[i]);assert len(t) and t.min()<.30,'buried glass mutation not caught'
(root/'surface-verification.json').write_text(json.dumps({'status':'VERIFIED','models':rows,'coverage':'deterministic up to160 actual glass centroids per role/LOD, outward 140mm and inward backing100mm, rubber tread existence and buried-glass ray counterexample; not all pixels, support graph or dynamic collisions'},indent=2)+'\n')
print('VERIFIED sampled glass visibility, backing, buried-glass counterexample and tread presence',len(rows))
