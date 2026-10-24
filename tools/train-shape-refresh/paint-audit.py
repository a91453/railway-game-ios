"""Verify paint-only subdivision stays on prior actual triangles with equal area."""
from pathlib import Path
from collections import Counter
import sys,struct,json
import numpy as np
root,prior=map(Path,sys.argv[1:3])
def triangles(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b''.join(b[start+i*52+4+j*16:start+i*52+16+j*16] for j in range(3)) for i in range(n)]
def points(ts):return np.array([struct.unpack('<9f',t) for t in ts],dtype=float).reshape(-1,3,3)
records=[]
for id in ['refresh-700t-cab','refresh-700t-tail']:
 old=triangles(prior/'models'/(id+'.m3dmodel'));new=triangles(root/'models'/(id+'.m3dmodel'))
 removed=list((Counter(old)-Counter(new)).elements());added=list((Counter(new)-Counter(old)).elements())
 assert removed and added,(id,'no geometry subdivision to check')
 p,q=points(removed),points(added);a=p[:,0];u=p[:,1]-a;v=p[:,2]-a
 normals=np.cross(u,v);area=np.linalg.norm(normals,axis=1)/2;normals/=2*area[:,None]
 uu=np.einsum('ij,ij->i',u,u);vv=np.einsum('ij,ij->i',v,v);uv=np.einsum('ij,ij->i',u,v);den=uu*vv-uv*uv
 assigned=np.zeros(len(p));maxdistance=0.
 for t in q:
  w=t[None,:,:]-a[:,None,:]
  distance=np.abs(np.einsum('ik,ijk->ij',normals,w))
  wu=np.einsum('ik,ijk->ij',u,w);wv=np.einsum('ik,ijk->ij',v,w)
  bu=(vv[:,None]*wu-uv[:,None]*wv)/den[:,None];bv=(uu[:,None]*wv-uv[:,None]*wu)/den[:,None]
  valid=np.all((distance<0.00002)&(bu>=-0.0001)&(bv>=-0.0001)&(bu+bv<=1.0001),axis=1)
  ids=np.flatnonzero(valid);assert len(ids)==1,(id,'new face leaves original triangle',ids.tolist(),t.tolist())
  i=ids[0];assigned[i]+=np.linalg.norm(np.cross(t[1]-t[0],t[2]-t[0]))/2
  maxdistance=max(maxdistance,float(distance[i].max()))
 assert np.allclose(assigned,area,rtol=0.00005,atol=0.000002),(id,'area changed',float(np.max(abs(assigned-area))))
 records.append({'id':id,'unchanged_geometry_triangles':len(new)-len(added),'prior_triangles_subdivided':len(p),'final_subtriangles':len(q),'maximum_plane_error_m':maxdistance,'area_preserved':True})
(root/'paint-verification.json').write_text(json.dumps({'status':'VERIFIED','checks':['every added triangle contained in one prior triangle','prior triangle area preserved','geometry unchanged except coplanar paint tessellation'],'models':records,'limits':'Float32 tolerance 20 micrometres; not engineering accuracy'},indent=2)+'\n')
print('VERIFIED paint-only geometry',records)
