"""Kaohsiung output geometry probes. Distances in metres; display acceptance only."""
import json,struct,sys
from collections import Counter
from pathlib import Path
import numpy as np

def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 t=np.array([[struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)] for i in range(n)])
 f=np.array([struct.unpack_from('<I',b,o+i*52)[0] for i in range(n)])
 return t,f

def rays(t,o,d,indices=False):
 e=t[:,1]-t[:,0];v=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,v.shape),v);a=np.sum(e*h,axis=1);valid=abs(a)>1e-9
 inv=np.divide(1,a,out=np.zeros_like(a),where=valid);s=o-t[:,0];u=np.sum(s*h,axis=1)*inv;q=np.cross(s,e);w=np.sum(q*d,axis=1)*inv;dist=np.sum(v*q,axis=1)*inv
 mask=valid&(u>=-1e-6)&(w>=-1e-6)&(u+w<=1.000001)&(dist>1e-6)
 return (np.flatnonzero(mask),dist[mask]) if indices else dist[mask]

def glass(t,f):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);n/=np.linalg.norm(n,axis=1)[:,None];c=t.mean(axis=1)
 ids=np.flatnonzero(((f&2)>0)&(((abs(n[:,1])>.95)&(c[:,0]<10))|((n[:,0]>.65)&(c[:,0]>10)&(c[:,2]>2.3))))
 assert len(ids)>20,'glass missing'
 # Wiper rods are expected, thin supported occluders. Exclude only those actual
 # non-glass triangles in their bounded mechanism envelope, never the shell/frame.
 wiper=((f&2)==0)&(t[:,:,0].min(axis=1)>10)&(t[:,:,2].min(axis=1)>=2.20)&(t[:,:,2].max(axis=1)<2.75)&(abs(t[:,:,1]).min(axis=1)>.93)&(abs(t[:,:,1]).max(axis=1)<1.33)&(np.ptp(t[:,:,0],axis=1)<.30)
 for i in ids:
  if abs(n[i,1])>.95 and n[i,1]*c[i,1]<0:continue
  surface=t[~wiper]
  ds=rays(surface,c[i]+n[i]*.25,-n[i]);assert len(ds) and min(ds)>.247,'glass buried'
  support=rays(t[(f&2)==0],c[i]-n[i]*.001,-n[i])
  assert len(support) and min(support)<.055,'glass floating / no physical backing'
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

def colors(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 return np.array([struct.unpack_from('<I',b,o+i*52+16)[0] for i in range(n)])

def paint(t,c):
 def sample(y,z):
  ids,ds=rays(t,np.array([11.6,y,z]),np.array([-1.,0.,0.]),True)
  assert len(ds),'front material missing'
  v=int(c[ids[np.argmin(ds)]]);return np.array([v&255,(v>>8)&255,(v>>16)&255])/255
 def navy(v):return v[2]>v[0]*1.85 and v[2]>v[1]*1.5
 assert navy(sample(-1.0,3.10)),'destination not on observer-left'
 assert not navy(sample(1.0,3.10)),'wrong-side destination retained'
 assert navy(sample(0,2.65)),'central opaque mask'
 for y,z in [(0,1.68),(0,3.35)]:
  v=sample(y,z);assert v[1]>v[0]*1.8 and v[2]>v[0]*1.8,'teal shell region'
 v=sample(0,1.88);assert max(v)-min(v)<.13 and np.mean(v)>.35,'white U stripe'

def crown_paint(t,c):
 def at(y,z):
  ids,ds=rays(t,np.array([11.6,y,z]),np.array([-1.,0.,0.]),True)
  v=int(c[ids[np.argmin(ds)]]);return np.array([v&255,(v>>8)&255,(v>>16)&255])/255
 v=at(.8,3.285);assert v[2]>v[0]*1.85 and v[2]>v[1]*1.5,'crown lower edge still a flat colour block'
 for y in [-1.45,1.45]:
  v=at(y,3.22);assert v[1]>v[0]*1.8 and v[2]>v[0]*1.8,'upper mask corner remains square'

def cab_shape(t):
 # The true ring head leaves a visible socket; R1's solid grey block must fail.
 ds=rays(t,np.array([11.4725,0.,.785]),np.array([-1.,0.,0.]))
 assert len(ds) and min(ds)>.532,'coupler socket filled'
 # Lower cheeks occupy the front shell while leaving the central notch open.
 for y in [-.8,.8]:
  ds=rays(t,np.array([11.3,y,.97]),np.array([-1.,0.,0.]))
  assert len(ds) and min(ds)<1.0,'lower cheek missing'

def reject(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('mutation escaped')

if __name__=='__main__':
 root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());rows=[]
 for r in m['models']:
  if r.get('native_kind')=='assembly':continue
  t,f=read(root/r['native']);cab='-t' not in r['id'];glass(t,f);wheels(t);equipment(t);gangway(t,10.9725 if cab else 10.78,cab)
  if cab:
   cab_shape(t);paint(t,colors(root/r['native']));crown_paint(t,colors(root/r['native']))
  # Shift the actual complete side-pane solid, not an invented test triangle.
  c=t.mean(axis=1);sel=((f&2)>0)&(c[:,0]>-8.1)&(c[:,0]<-6.6)&(c[:,1]>1.59)
  assert sel.sum()>5
  broken=t.copy();broken[sel,:,1]-=.15;reject(lambda:glass(broken,f))
  if cab:
   sel=((f&2)>0)&(t[:,:,0].min(axis=1)>10)
   assert sel.sum()>10
   buried=t.copy();buried[sel,:,0]-=.15;reject(lambda:glass(buried,f))
   floating=t.copy();floating[sel,:,0]+=.09;reject(lambda:glass(floating,f))
   # A real two-triangle cap placed over the socket is rejected.
   cap=np.array([[[10.9725,-.13,.70],[10.9725,.13,.70],[10.9725,.13,.88]],[[10.9725,-.13,.70],[10.9725,.13,.88],[10.9725,-.13,.88]]])
   reject(lambda:cab_shape(np.concatenate([t,cap])))
   sign=((t[:,:,0]>10).all(axis=1)&(t[:,:,1]<-.69).all(axis=1)&(t[:,:,1]>-1.38).all(axis=1)&(t[:,:,2]>=2.95).all(axis=1)&(t[:,:,2]<=3.21).all(axis=1))
   assert sign.sum()>10,'destination solid absent'
   wrong=t.copy();wrong[sign,:,1]*=-1
   reject(lambda:paint(wrong,colors(root/r['native'])))
   flat=colors(root/r['native']).copy();centres=t.mean(axis=1)
   selected=(centres[:,0]>10)&(abs(centres[:,1])<1.3)&(centres[:,2]>3.26)&(centres[:,2]<3.34)
   flat[selected]=0xffc0d345
   reject(lambda:crown_paint(t,flat))
  sel=(abs(t[:,:,0]+8.3)<.426).all(axis=1)&(abs(t[:,:,1]-.7175)<.071).all(axis=1)&(t[:,:,2]<.851).all(axis=1)
  broken=t.copy();broken[sel,:,2]+=.035;reject(lambda:wheels(broken))
  sel=(abs(t[:,:,0]-6.9)<1.451).all(axis=1)&(t[:,:,2]>=3.5999).all(axis=1)
  broken=t.copy();broken[sel,:,2]+=.08;reject(lambda:equipment(broken))
  rows.append({'id':r['id'],'glass_visibility_and_backing':True,'eight_wheels_rail_and_clearance':True,'roof_contact':True,'gangway_plane':True,'actual_glass_bury_150mm_wheel_lift_35mm_roof_lift_80mm_rejected':True,'cab_front_bury_float_socket_cap_and_wrong_side_destination_rejected':cab,'actual_flat_crown_repaint_rejected':cab})
 for unit in ['dm1','t','dm2']:
  a=next(r for r in m['models'] if r['id']=='kaohsiung-'+unit);b=next(r for r in m['models'] if r['id']==a['id']+'-far')
  assert a['triangles']<=15000 and b['triangles']<a['triangles']/2,(unit,a['triangles'],b['triangles'])
  for k in ['minimum','maximum']:assert np.max(abs(np.array(a[k])-b[k]))<.0001
 for r in m['models']:
  if r.get('native_kind')=='assembly':
   s=json.loads((root/r['native']).read_text());assert [p['rotation_degrees'] for p in s['placements']]==[0,0,180]
   assert [p['translation'][0] for p in s['placements']]==[21.7525,0,-21.7525]
   assert r['triangles']< (120000 if r['id'].endswith('far') else 240000)
 previous_rejected=[];protected=[]
 if '--previous' in sys.argv:
  previous=Path(sys.argv[sys.argv.index('--previous')+1])
  for r in m['models']:
   if r.get('native_kind')=='assembly':continue
   old,old_f=read(previous/r['native']);new,new_f=read(root/r['native'])
   def signature(t,f):
    selected=(t[:,:,0]<=9.0).all(axis=1)
    return Counter((tuple(np.round(q.flatten()*1e5).astype(int)),int(v)) for q,v in zip(t[selected],f[selected]))
   assert signature(old,old_f)==signature(new,new_f),'changed protected body/hardware geometry or flags'
   trailer='-t' in r['id']
   if trailer:assert (previous/r['native']).read_bytes()==(root/r['native']).read_bytes(),'T payload changed'
   protected.append({'id':r['id'],'unchanged_geometry_flags_triangles_x_le_9m':sum(signature(old,old_f).values()),'trailer_full_bytes_unchanged':trailer})
   if not trailer:
    reject(lambda:crown_paint(old,colors(previous/r['native'])));previous_rejected.append(r['id'])
 report={'protected_previous':protected,'true_r2_front_paint_rejected':previous_rejected,'status':'VERIFIED','models':rows,'limits':'Triangle-centroid exterior glass rays, 8 tyre envelopes and roof central support samples; no exhaustive self-intersection or engineering/appearance/device acceptance.'}
 (root/'kaohsiung-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
