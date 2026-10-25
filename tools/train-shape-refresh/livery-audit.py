"""Audit a narrower nose livery on real native triangles, independently of recipe."""
from pathlib import Path
from collections import Counter
import sys,struct,json
import numpy as np
root,prior=map(Path,sys.argv[1:3]);manifest=json.loads((root/'manifest.json').read_text());records=[]
white=manifest['livery']['high_speed']['body_argb'];black=manifest['livery']['high_speed']['accent_argb'];teal=0xff8c8c3e
allowed={white,black,teal}
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def points(ts):return np.array([[struct.unpack_from('<fff',t,4+j*16) for j in range(3)] for t in ts])
def geometry(t):return b''.join(t[4+j*16:16+j*16] for j in range(3))
def clip(poly,fn):
 out=[]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  da,db=fn(a),fn(b);ia,ib=da>=0,db>=0
  if ia:out.append(a)
  if ia!=ib:out.append(a+(b-a)*(da/(da-db)))
 return out
def audit_shape(old,new):
 before=Counter(geometry(t) for t in old);after=Counter(geometry(t) for t in new)
 p=np.array([struct.unpack('<9f',t) for t in (before-after).elements()]).reshape(-1,3,3)
 q=np.array([struct.unpack('<9f',t) for t in (after-before).elements()]).reshape(-1,3,3)
 assert len(p) and len(q)
 a=p[:,0];u=p[:,1]-a;v=p[:,2]-a;cross=np.cross(u,v);area2=np.linalg.norm(cross,axis=1);normals=cross/area2[:,None]
 uu=np.einsum('ij,ij->i',u,u);vv=np.einsum('ij,ij->i',v,v);uv=np.einsum('ij,ij->i',u,v);den=uu*vv-uv*uv
 low,high=p.min(axis=1),p.max(axis=1);assigned=np.zeros(len(p));maximum_error=0.
 def overlaps(t):
  bounds=np.all((high>=t.min(axis=0)-.00002)&(low<=t.max(axis=0)+.00002),axis=1)
  distance=np.abs(np.einsum('ik,ijk->ij',normals,t[None,:,:]-a[:,None,:]))
  candidates=np.flatnonzero(bounds&np.all(distance<.00002,axis=1));out=[]
  for i in candidates:
   w=t-a[i];wu=w@u[i];wv=w@v[i]
   poly=list(np.column_stack(((vv[i]*wu-uv[i]*wv)/den[i],(uu[i]*wv-uv[i]*wu)/den[i])))
   for fn in [lambda x:x[0],lambda x:x[1],lambda x:1-x[0]-x[1]]:poly=clip(poly,fn)
   if len(poly)<3:continue
   overlap=abs(sum(x[0]*y[1]-x[1]*y[0] for x,y in zip(poly,poly[1:]+poly[:1])))*area2[i]/2
   if overlap>1e-10:out.append((i,float(overlap)))
  return out
 for t in q:
  matches=overlaps(t);actual=np.linalg.norm(np.cross(t[1]-t[0],t[2]-t[0]))/2;covered=sum(x[1] for x in matches)
  assert np.isclose(covered,actual,rtol=.00015,atol=.000003),('new face leaves previous hull',covered,actual)
  for i,area in matches:assigned[i]+=area
  maximum_error=max(maximum_error,abs(covered-actual))
 assert np.allclose(assigned,area2/2,rtol=.00015,atol=.000003),('prior area not preserved',float(np.max(abs(assigned-area2/2))))
 t=q[0];normal=np.cross(t[1]-t[0],t[2]-t[0]);normal/=np.linalg.norm(normal)
 assert sum(x[1] for x in overlaps(t+normal*.005))<np.linalg.norm(np.cross(t[1]-t[0],t[2]-t[0]))*.49,'5mm displaced hull mutation accepted'
 return {'prior_retessellated_triangles':len(p),'final_retessellated_triangles':len(q),'bidirectional_coplanar_area_preserved':True,'maximum_triangle_area_error_m2':maximum_error,'five_mm_hull_displacement_rejected':True}
def metrics(ts):
 ps=points(ts);colors=np.array([[struct.unpack_from('<I',t,16+j*16)[0] for j in range(3)] for t in ts])
 green=np.all(colors==teal,axis=1)&np.all(ps[:,:,0]>6.6999,axis=1)
 cross=np.cross(ps[:,1]-ps[:,0],ps[:,2]-ps[:,0]);front_area=float(np.maximum(cross[green,0],0).sum()/2)
 front_white=[p for t in ts for p in [struct.unpack_from('<fffI',t,4+j*16) for j in range(3)] if p[0]>11.8 and abs(p[1])<.25 and p[3]==white]
 return {'teal_front_projected_area_m2':front_area,'white_tip_low_z_m':min(p[2] for p in front_white)}
for id in ['refresh-e200','refresh-700t-middle','refresh-700t-panto','metro-four-leading']:
 for ext in ['.m3dmodel','.glb']:assert (root/'models'/(id+ext)).read_bytes()==(prior/'models'/(id+ext)).read_bytes(),id+ext
 records.append({'id':id,'native_and_glb_byte_identical':True})
for id,sign in [('refresh-700t-cab',1),('refresh-700t-tail',-1)]:
 old,new=read(prior/'models'/(id+'.m3dmodel')),read(root/'models'/(id+'.m3dmodel'))
 removed=list((Counter(old)-Counter(new)).elements());added=list((Counter(new)-Counter(old)).elements())
 for t in removed+added:
  for j in range(3):
   x,y,z,c=struct.unpack_from('<fffI',t,4+j*16);assert x*sign>=3.6999 and c in allowed,(id,'change outside nose livery',x,c)
 records.append({'id':id,'unchanged_triangles_byte_identical':sum((Counter(old)&Counter(new)).values()),'only_nose_white_teal_black_changed':True,**audit_shape(old,new)})
old=metrics(read(prior/'models/refresh-700t-cab.m3dmodel'));new=metrics(read(root/'models/refresh-700t-cab.m3dmodel'))
assert new['teal_front_projected_area_m2']<old['teal_front_projected_area_m2']*.8,(old,new)
assert new['white_tip_low_z_m']<1.10,(old,new)
for old_m,new_m in zip(json.loads((prior/'manifest.json').read_text())['models'],manifest['models']):
 assert old_m['minimum']==new_m['minimum'] and old_m['maximum']==new_m['maximum'],new_m['id']
assert manifest['assemblies']==json.loads((prior/'manifest.json').read_text())['assemblies']
result={'status':'VERIFIED','prior_actual_delivery':old,'final_actual_delivery':new,'teal_front_projected_area_ratio':new['teal_front_projected_area_m2']/old['teal_front_projected_area_m2'],'scope':records,'limits':'sum of front-facing triangle projections in model coordinates (can include occlusion), not raster visible-pixel area, photographic similarity, engineering dimensions or owner approval; coplanar overlap tolerance20micrometres, areas3e-6m2'}
(root/'livery-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
