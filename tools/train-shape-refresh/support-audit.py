"""Sample exported glazing support with actual triangle rays, independently of Swift."""
import sys,json,struct
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());records=[]
def read(path):
 b=path.read_bytes();count,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 ps=[];cs=[]
 for i in range(count):
  tri=[]; colors=[]
  for j in range(3):
   x,y,z,c=struct.unpack_from('<fffI',b,start+i*52+4+j*16);tri.append((x,y,z));colors.append(c&0xffffff)
  ps.append(tri);cs.append(colors)
 return np.array(ps),np.array(cs)
def nearest(origin,direction,triangles):
 a=triangles[:,0];e1=triangles[:,1]-a;e2=triangles[:,2]-a;h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-10
 f=np.zeros_like(det);f[valid]=1/det[valid];s=origin-a;u=f*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=f*np.einsum('j,ij->i',direction,q);t=f*np.einsum('ij,ij->i',e2,q)
 mask=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>0.0001)
 return float(np.min(t[mask])) if mask.any() else float('inf')
for m in manifest['models']:
 if m['category']!='section':continue
 p,c=read(root/m['native']);glass_color=(79|(90<<8)|(97<<16)) if m['id']=='refresh-e200' else manifest['livery']['high_speed']['glass_argb']&0xffffff
 pane_color=(107|(122<<8)|(132<<16))
 glass=np.all(c==glass_color,axis=1) | (np.all(c==pane_color,axis=1) if m['id']!='refresh-e200' else False);other=p[~glass];distances=[]
 for t in p[glass]:
  n=np.cross(t[1]-t[0],t[2]-t[0]);area=np.linalg.norm(n)/2
  if area<0.03:continue
  n/=np.linalg.norm(n);centre=t.mean(axis=0)
  distances.append(min(nearest(centre,n,other),nearest(centre,-n,other)))
 assert distances,m['id']
 displaced=centre+n*0.75
 assert min(nearest(displaced,n,other),nearest(displaced,-n,other))>0.12, 'Floating-glass mutation was not rejected'
 records.append({'id':m['id'],'glazing_face_samples':len(distances),'within_120mm':sum(x<=0.12 for x in distances),'maximum_distance_m':max(distances) if np.isfinite(max(distances)) else None,'status':'VERIFIED' if all(x<=0.12 for x in distances) else 'UNVERIFIED'})
(root/'support-verification.json').write_text(json.dumps({'method':'two-sided normal rays from actual glazing triangle centroids to non-glass triangles; 120mm threshold','models':records,'limits':'sampled backing distance only; not a full contact graph, equipment support or wheel clearance proof'},indent=2)+'\n')
print(json.dumps(records))
assert all(m['status']=='VERIFIED' for m in records), 'Unsupported glazing sample'
