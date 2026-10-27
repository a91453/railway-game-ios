import json,sys,struct
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());rows=[]
def hit(tri,o,d):
 a=tri[:,0];e=tri[:,1]-a;f=tri[:,2]-a;h=np.cross(d,f);det=(e*h).sum(1);ok=abs(det)>1e-11;inv=np.divide(1,det,out=np.zeros_like(det),where=ok);s=o-a;u=(s*h).sum(1)*inv;q=np.cross(s,e);v=(q*d).sum(1)*inv;t=(f*q).sum(1)*inv
 return t[ok&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>1e-5)]
for rec in m['models']:
 if rec['category']!='section':continue
 data=(root/rec['native']).read_bytes();n,meta=struct.unpack_from('<II',data,8);s=16+(meta+3)//4*4
 d=np.frombuffer(data[s:],dtype=np.dtype([('f','<u4'),('v',[('p','<f4',(3,)),('c','<u4')],(3,))]));p=d['v']['p'].astype(float);col=d['v']['c'][:,0];cent=p.mean(1)
 normals=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);normals/=np.linalg.norm(normals,axis=1)[:,None]
 ids=np.flatnonzero(col==m['palette']['glass']);parents={int(i):int(i) for i in ids};seen={}
 def find(i):
  while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
  return i
 for i in ids:
  for pt in p[i]:
   key=tuple(np.round(pt,5));j=seen.setdefault(key,int(i));parents[find(int(i))]=find(j)
 i=next(int(i) for i in ids if abs(cent[i,0])<4 and normals[i,1]>.99 and cent[i,1]>1.44)
 component=np.array([j for j in ids if find(int(j))==find(i)]);outside=normals[i];o=cent[i]
 # Actual whole closed glass component translation; old pane geometry is absent.
 for kind,delta in [('buried',-.20),('floating',.30)]:
  modified=p.copy();modified[component]+=outside*delta;origin=modified[i].mean(0)
  others=np.delete(modified,component,axis=0)
  if kind=='buried':
   hits=hit(others,origin+outside*.0001,outside);assert len(hits) and hits.min()<.20,(rec['id'],'buried component not obstructed')
  else:
   hits=hit(others,origin-outside*.0001,-outside);assert len(hits) and hits.min()>.10,(rec['id'],'floating component unexpectedly backed')
 rows.append({'id':rec['id'],'actual_glass_component_triangles':len(component),'buried_200mm_rejected':True,'floating_300mm_rejected':True})
(root/'independent-mutations.json').write_text(json.dumps({'status':'VERIFIED','method':'translate entire real connected side glazing solid, remove its previous geometry, ray against remaining actual final triangles; outward obstruction200mm/inward backing100mm','models':rows},indent=2))
print('VERIFIED actual connected glazing mutation pairs',len(rows))
