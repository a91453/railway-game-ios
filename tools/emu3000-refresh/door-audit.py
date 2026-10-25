"""Door visibility against actual native triangles, independent of recipe surface math."""
import sys,json,struct
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());glass=int(m['palette']['glass'])
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 a=[ [struct.unpack_from('<fffI',b,start+i*52+4+j*16) for j in range(3)] for i in range(n)]
 return np.array([[v[:3] for v in t] for t in a]),np.array([t[0][3] for t in a])
def hits(o,d,p):
 a=p[:,0];e=p[:,1]-a;f=p[:,2]-a;h=np.cross(d,f);det=np.einsum('ij,ij->i',e,h);inv=np.divide(1,det,out=np.zeros(len(det)),where=abs(det)>1e-12);s=o-a;u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e);v=inv*np.einsum('j,ij->i',d,q);t=inv*np.einsum('ij,ij->i',f,q)
 return np.where((abs(det)>1e-12)&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>=0),t,np.inf)
rows=[]
for rec in m['models']:
 if rec['category']!='section':continue
 id=rec['id']
 p,c=read(root/rec['native']);bad=0;total=0;worst=0;overlap=0
 normals=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);normals/=np.linalg.norm(normals,axis=1)[:,None];centres=p.mean(axis=1)
 doors=[8.5,-5.3,-7.0] if 'tail' in id else [-8.5,5.3,7.0] if '-ed' in id else [-8,8]
 for i in np.where((c==glass)&(abs(normals[:,1])>0.7)&(normals[:,1]*centres[:,1]>0)&(abs(centres[:,1])>1.0)&(np.min(np.abs(centres[:,0,None]-doors),axis=1)<0.25))[0]:
  d=np.array([0.,np.sign(centres[i,1]),0.]);o=centres[i]+d*.4;t=hits(o,-d,p);near=t.min();total+=1
  if near<.397:bad+=1;worst=max(worst,.4-near)
  if ((abs(t-.4)<.001)&(c!=glass)).any():overlap+=1
 print(id,'door_glass_samples',total,'occluded',bad,'coplanar_other_color',overlap,'max_cover_m',worst)
 assert bad==0 and overlap==0,'visible door glazing occlusion/depth conflict'
 rows.append({'id':id,'actual_front_glazing_samples':total,'occluded_samples':bad,'coplanar_non_glass_samples':overlap})

(root/'door-verification.json').write_text(json.dumps({'status':'VERIFIED','method':'all outward door glass triangle centroids raycast against all actual triangles; reject more than3mm cover and1mm non-glass depth conflicts','models':rows,'limits':'centroid static surface visibility; Swift also tests an inward glazing mutation; not Metal device verification'},indent=2)+'\n')
