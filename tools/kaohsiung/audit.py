"""Kaohsiung output geometry probes. Distances in metres; display acceptance only."""
import json,struct,sys
from pathlib import Path
import numpy as np

def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 t=np.array([[struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)] for i in range(n)])
 f=np.array([struct.unpack_from('<I',b,o+i*52)[0] for i in range(n)])
 return t,f

def rays(t,o,d):
 e=t[:,1]-t[:,0];v=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,v.shape),v);a=np.sum(e*h,axis=1);valid=abs(a)>1e-9
 inv=np.divide(1,a,out=np.zeros_like(a),where=valid);s=o-t[:,0];u=np.sum(s*h,axis=1)*inv;q=np.cross(s,e);w=np.sum(q*d,axis=1)*inv;dist=np.sum(v*q,axis=1)*inv
 return dist[valid&(u>=-1e-6)&(w>=-1e-6)&(u+w<=1.000001)&(dist>1e-6)]

def glass(t,f):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);n/=np.linalg.norm(n,axis=1)[:,None];c=t.mean(axis=1)
 ids=np.flatnonzero(((f&2)>0)&(((abs(n[:,1])>.95)&(c[:,0]<10))|((n[:,0]>.9)&(c[:,0]>10)&(c[:,2]>2.3))))
 assert len(ids)>20,'glass missing'
 for i in ids:
  if abs(n[i,1])>.95 and n[i,1]*c[i,1]<0:continue
  if n[i,0]>.9 and c[i,0]<10:continue
  ds=rays(t,c[i]+n[i]*.25,-n[i]);assert len(ds) and min(ds)>.247,'glass buried'
 return ids

def wheels(t):
 for x in [-8.30,-6.00,6.00,8.30]:
  for y in [-.7175,.7175]:
   sel=(abs(t[:,:,0]-x)<.426).all(axis=1)&(abs(t[:,:,1]-y)<.071).all(axis=1)&(t[:,:,2]<.851).all(axis=1)
   p=t[sel].reshape(-1,3);assert len(p)>=24 and abs(p[:,2].min())<1e-5,'wheel lifted'
   ds=rays(t,np.array([x,y,.86]),np.array([0.,0.,1.]));assert len(ds) and min(ds)>.15,'wheel clearance'

def equipment(t):
 for x in [-6.9,6.9]:
  sel=(abs(t[:,:,0]-x)<1.451).all(axis=1)&(t[:,:,2]>=3.5999).all(axis=1)
  base=t[sel,:,2].min();assert abs(base-3.60)<1e-4,'equipment lost roof contact'
  ds=rays(t[~sel],np.array([x,0.,base+.01]),np.array([0.,0.,-1.]));assert len(ds) and min(ds)<.011,'roof missing under equipment'

def gangway(t,half,cab):
 for sign in ([-1] if cab else [-1,1]):
  p=t.reshape(-1,3);assert len(p[(abs(p[:,0]-sign*half)<1e-4)&(p[:,2]>3.1)])>=4,'gangway plane'

def reject(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('mutation escaped')

root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());rows=[]
for r in m['models']:
 if r.get('native_kind')=='assembly':continue
 t,f=read(root/r['native']);cab='-t' not in r['id'];glass(t,f);wheels(t);equipment(t);gangway(t,10.9725 if cab else 10.78,cab)
 # Shift the actual complete side-pane solid, not an invented test triangle.
 c=t.mean(axis=1);sel=((f&2)>0)&(c[:,0]>-8.1)&(c[:,0]<-6.6)&(c[:,1]>1.59)
 assert sel.sum()>5
 broken=t.copy();broken[sel,:,1]-=.15;reject(lambda:glass(broken,f))
 sel=(abs(t[:,:,0]+8.3)<.426).all(axis=1)&(abs(t[:,:,1]-.7175)<.071).all(axis=1)&(t[:,:,2]<.851).all(axis=1)
 broken=t.copy();broken[sel,:,2]+=.035;reject(lambda:wheels(broken))
 sel=(abs(t[:,:,0]-6.9)<1.451).all(axis=1)&(t[:,:,2]>=3.5999).all(axis=1)
 broken=t.copy();broken[sel,:,2]+=.08;reject(lambda:equipment(broken))
 rows.append({'id':r['id'],'glass_visibility':True,'eight_wheels_rail_and_clearance':True,'roof_contact':True,'gangway_plane':True,'actual_glass_bury_150mm_wheel_lift_35mm_roof_lift_80mm_rejected':True})
for unit in ['dm1','t','dm2']:
 a=next(r for r in m['models'] if r['id']=='kaohsiung-'+unit);b=next(r for r in m['models'] if r['id']==a['id']+'-far')
 assert a['triangles']<=15000 and b['triangles']<a['triangles']/2,(unit,a['triangles'],b['triangles'])
 for k in ['minimum','maximum']:assert np.max(abs(np.array(a[k])-b[k]))<.0001
for r in m['models']:
 if r.get('native_kind')=='assembly':
  s=json.loads((root/r['native']).read_text());assert [p['rotation_degrees'] for p in s['placements']]==[0,0,180]
  assert [p['translation'][0] for p in s['placements']]==[21.7525,0,-21.7525]
  assert r['triangles']< (120000 if r['id'].endswith('far') else 240000)
report={'status':'VERIFIED','models':rows,'limits':'Triangle-centroid exterior glass rays, 8 tyre envelopes and roof central support samples; no exhaustive self-intersection or engineering/appearance/device acceptance.'}
(root/'kaohsiung-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
