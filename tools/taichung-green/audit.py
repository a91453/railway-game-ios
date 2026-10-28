#!/usr/bin/env python3
"""TMRT-specific probes on exported triangles, including destructive counterexamples.
No engineering accuracy or exhaustive collision claim. Requires numpy (scratch venv).
"""
import json,struct,sys
from collections import Counter
from pathlib import Path
import numpy as np

def read(p,with_colors=False):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);off=16+(size+3)//4*4
 t=[];flags=[];colors=[]
 for i in range(n):
  flags.append(struct.unpack_from('<I',b,off+i*52)[0]);t.append([struct.unpack_from('<fffI',b,off+i*52+4+j*16)[:3] for j in range(3)])
  colors.append([struct.unpack_from('<I',b,off+i*52+16+j*16)[0] for j in range(3)])
 return (np.array(t),np.array(flags),np.array(colors)) if with_colors else (np.array(t),np.array(flags))
def normals(t):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);return n/np.linalg.norm(n,axis=1)[:,None]
def hits(t,o,d,with_indices=False):
 e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,e2.shape),e2);a=np.sum(e1*h,axis=1);ok=np.abs(a)>1e-9
 inv=np.divide(1,a,out=np.zeros_like(a),where=ok);s=o-t[:,0];u=inv*np.sum(s*h,axis=1);q=np.cross(s,e1);v=inv*np.sum(d*q,axis=1);dist=inv*np.sum(e2*q,axis=1)
 sel=ok&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1+1e-6)&(dist>1e-6)
 return (np.flatnonzero(sel),dist[sel]) if with_indices else dist[sel]
def visible(t,f):
 n=normals(t);c=t.mean(axis=1)
 # True exterior glass faces only. Wiper lies below the windscreen samples.
 chosen=((f&2)!=0)&(((c[:,0]>9.4)&(n[:,0]>.7)&(c[:,2]>2.40))|((abs(c[:,1])>1.44)&(n[:,1]*c[:,1]>.9)))
 ids=np.flatnonzero(chosen);assert len(ids)>20,'missing glass'
 blocked=[]
 for i in ids:
  d=n[i];ds=hits(t,c[i]+d*.5,-d)
  if len(ds) and min(ds)<.497:blocked.append(int(i))
 assert not blocked,f'glass buried/occluded: {blocked[:8]}'
 return ids

def wheels(t):
 # Eight actual tyres: 2 bogies x 2 axles x 2 rails. Derived design stations
 # are photo estimates; the 1.435m gauge alone is an official dimension.
 for x in [-7.9,-5.8,5.8,7.9]:
  for y in [-.7175,.7175]:
   p=t.reshape(-1,3);q=p[(abs(p[:,0]-x)<.391)&(abs(p[:,1]-y)<.066)&(p[:,2]<.781)]
   assert len(q)>10 and abs(q[:,2].min())<1e-5,'wheel lifted from rail'
   assert q[:,2].max()<.781,'wheel envelope'
   # Actual body underfloor vertices above each tyre (not a global bound).
   ds=hits(t,np.array([x,y,.79]),np.array([0.,0,1.]))
   assert len(ds) and min(ds)>.10,'wheel/body clearance'

def gangway(t):
 p=t.reshape(-1,3)
 contact=p[(abs(p[:,0]+11.085)<1e-5)&(abs(p[:,1])>.75)&(p[:,2]>3.1)]
 assert len(contact)>=4,'gangway does not reach common coupling plane'

def aperture(t):
 for y in [-.56,-.45,.45,.56]:
  for h in [.70,.89]:
   ds=hits(t,np.array([11.5,y,h]),np.array([-1.,0,0]))
   assert not len(ds) or min(ds)>1.6,'front opening filled'
 ds=hits(t,np.array([11.5,0,.73]),np.array([-1.,0,0]))
 assert len(ds) and min(ds)>.46,'coupler socket has no recess'

def mounts(t):
 # A ray exiting with the outward normal verifies that each gap probe lies
 # inside actual support material, rather than merely near another component.
 for x in [-6.85,6.85,10.12]:
  d=np.array([0.,1,0]);ids,ds=hits(t,np.array([x,0,.86]),d,True)
  assert len(ds),'missing bogie/coupler mounting material'
  first=ids[np.argmin(ds)]
  assert normals(t[first:first+1])[0].dot(d)>.5,'probe is outside support material'

def roof(t):
 for x in [-7.3,7.1]:
  ds=hits(t[t[:,:,2].max(axis=1)<3.651],np.array([x,0,3.66]),np.array([0,0,-1.]));assert len(ds) and min(ds)<.10,'roof support missing'
  # Equipment base touches central roof ridge; no invented pantograph.
  p=t.reshape(-1,3);q=p[(abs(p[:,0]-x)<1.86)&(abs(p[:,1])<.826)&(p[:,2]>=3.649)]
  assert len(q) and abs(q[:,2].min()-3.65)<1e-4,'equipment base unsupported'

def rejected(call):
 try:call()
 except AssertionError:return
 raise AssertionError('fault example escaped')

def paint(t,c):
 # Compare the actual first visible material, rather than polygon declarations.
 # Coordinates are display-model/photo-fit probes, not prototype dimensions.
 def front(y,z):
  ids,ds=hits(t,np.array([12.,y,z]),np.array([-1.,0,0]),True)
  assert len(ids),'missing front surface'
  return c[ids[np.argmin(ds)],0]
 def rgb(value):return np.array([int(value)>>i&255 for i in [0,8,16]])
 for side in [-1,1]:
  dark=rgb(front(side*1.30,2.20));green=rgb(front(side*1.40,2.90));white=rgb(front(side*.99,2.60))
  # addFacet bakes mild face shading, so compare material ranges, not equality.
  assert max(dark)<100 and dark[2]>dark[0]*1.3,'outer cheek incorrectly white'
  assert green[1]>green[0]*1.3 and green[1]>green[2]*1.3,'upper green return missing'
  assert min(white)>130 and max(white)-min(white)<20,'white U overwritten'

root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());rows=[]
for r in m['models']:
 if r.get('native_kind')=='assembly':continue
 t,f,c=read(root/r['native'],True);ids=visible(t,f);wheels(t);roof(t);gangway(t);aperture(t);mounts(t);paint(t,c)
 broken_colors=c.copy();centres=t.mean(axis=1)
 # Repaint the real outer cheek material white, as in the true third version.
 cheek=(centres[:,0]>9)&(abs(centres[:,1])>1.2)&(centres[:,2]>2.0)&(centres[:,2]<2.4)
 white_ids,white_ds=hits(t,np.array([12.,.99,2.60]),np.array([-1.,0,0]),True)
 broken_colors[cheek]=c[white_ids[np.argmin(white_ds)],0]
 rejected(lambda:paint(t,broken_colors))
 broken=t.copy();n=normals(t);g=(f&2)!=0
 # Move the real connected glass inwards, including backs/walls.
 for i in np.flatnonzero(g):
  if abs(t[i].mean(axis=0)[1])>1.4:broken[i,:,1]-=np.sign(t[i].mean(axis=0)[1])*.10
  elif t[i].mean(axis=0)[0]>9:broken[i,:,0]-=.10
 rejected(lambda:visible(broken,f))
 broken=t.copy();c=t.mean(axis=1);sel=(abs(c[:,0]-7.9)<.40)&(abs(c[:,1]-.7175)<.07)&(c[:,2]<.79);broken[sel,:,2]+=.04
 rejected(lambda:wheels(broken))
 broken=t.copy();sel=broken[:,:,2]>=3.649;broken[:,:,2][sel]+=.06;rejected(lambda:roof(broken))
 broken=t.copy();c=t.mean(axis=1);sel=(c[:,0]<-10.5)&(c[:,2]>1.05)&(abs(c[:,1])<.81);broken[sel,:,0]+=.10
 rejected(lambda:gangway(broken))
 # A real front-facing plate closes the opening and coupler recess.
 plate=np.array([[[11.08,-.6,.55],[11.08,.6,.55],[11.08,.6,1.0]],
                 [[11.08,-.6,.55],[11.08,.6,1.0],[11.08,-.6,1.0]]])
 rejected(lambda:aperture(np.concatenate([t,plate])))
 # Delete the real bogie bolsters and coupler hanger, not a parameter stub.
 for x,length,width,lo,hi in [(-6.85,1.2,.8,.80,.94),(6.85,1.2,.8,.80,.94),(10.12,.7,.32,.79,1.04)]:
  remove=((abs(t[:,:,0]-x)<length/2+1e-4)&(abs(t[:,:,1])<width/2+1e-4)&(t[:,:,2]>=lo-1e-4)&(t[:,:,2]<=hi+1e-4)).all(axis=1)
  rejected(lambda:mounts(t[~remove]))
 rows.append({'white_cheek_repaint':'rejected','front_paint_first_visible_material':'VERIFIED','deleted_bogie_coupler_mounts':'rejected','filled_opening_and_socket':'rejected','gangway_retraction_100mm':'rejected','id':r['id'],'glass_exterior_faces':len(ids),'tyres':8,'glass_burial_100mm':'rejected','wheel_lift_40mm':'rejected','equipment_lift_60mm':'rejected'})
previous_rejected=[]
if '--previous' in sys.argv:
 previous=Path(sys.argv[sys.argv.index('--previous')+1])
 for r in m['models']:
  if r.get('native_kind')=='assembly':continue
  old,_=read(previous/r['native'])
  rejected(lambda:aperture(old));previous_rejected.append(r['id'])
paint_previous_rejected=[];paint_protection=[]
if '--previous-paint' in sys.argv:
 previous=Path(sys.argv[sys.argv.index('--previous-paint')+1])
 for r in m['models']:
  if r.get('native_kind')=='assembly':continue
  old,_,old_colors=read(previous/r['native'],True)
  rejected(lambda:paint(old,old_colors));paint_previous_rejected.append(r['id'])
  new,new_flags,new_colors=read(root/r['native'],True)
  _,old_flags=read(previous/r['native'])
  def protected(tri,flags,colors):
   allowed=((tri[:,:,0]>8.85)&(abs(tri[:,:,1])>.85)&(tri[:,:,2]>=1.24)&(tri[:,:,2]<=3.31)).all(axis=1)
   return Counter((tuple(np.round(p.flatten()*1e5).astype(int)),int(f)) for p,f in zip(tri[~allowed],flags[~allowed]))
  before=protected(old,old_flags,old_colors);after=protected(new,new_flags,new_colors)
  assert before==after,'change outside front/shoulder paint envelope'
  def protected_colors(tri,colors):
   return Counter((tuple(np.round(p*1e5).astype(int)),int(c)) for p,c in zip(tri.reshape(-1,3),colors.flatten()) if p[0]<=8.85)
  assert protected_colors(old,old_colors)==protected_colors(new,new_colors),'body colour changed outside cab'
  paint_protection.append({'id':r['id'],'unchanged_geometry_triangles_outside_paint_envelope':sum(before.values()),'body_colours_behind_cab_unchanged':True,'note':'Adjacent cab baked occlusion can change with added paint panels.'})
near=[r for r in m['models'] if r['id'].endswith(('dm1','dm2'))]
for a in near:
 b=next(r for r in m['models'] if r['id']==a['id']+'-far');assert b['triangles']<a['triangles']/2
 assert a['triangles']<=15000 and a['triangles']<=20000
 for k in ['minimum','maximum']:assert np.max(np.abs(np.array(a[k])-b[k]))<1e-4
for r in m['models']:
 if r.get('native_kind')=='assembly':
  s=json.loads((root/r['native']).read_text());assert [p['rotation_degrees'] for p in s['placements']]==[0,180]
  assert [p['translation'][0] for p in s['placements']]==[11.085,-11.085]
  assert r['triangles']<= (120000 if r['id'].endswith('far') else 240000)
report={'status':'VERIFIED','protected_previous_triangles':paint_protection,'true_previous_paint_rejected':paint_previous_rejected,'true_previous_socket_rejected':previous_rejected,'models':rows,'limits':'Exterior triangle-centroid rays; central roof contact, eight tyre envelopes; sampled visible paint. Not exhaustive collision/engineering accuracy/appearance acceptance.'}
(root/'taichung-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
