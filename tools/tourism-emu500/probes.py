"""Actual native probes. Ray method from project's new-taipei-lrt/audit.py.
Display constraints, not a vehicle engineering or exhaustive collision audit.
"""
import json,struct,sys,copy
from pathlib import Path
import numpy as np

def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 t=np.array([[struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)] for i in range(n)])
 f=np.array([struct.unpack_from('<I',b,o+i*52)[0] for i in range(n)])
 return t,f

def ray(t,o,d,indices=False):
 e=t[:,1]-t[:,0];v=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,v.shape),v);a=np.sum(e*h,axis=1);valid=abs(a)>1e-10
 inv=np.divide(1,a,out=np.zeros_like(a),where=valid);s=o-t[:,0];u=np.sum(s*h,axis=1)*inv;q=np.cross(s,e);w=np.sum(q*d,axis=1)*inv;dist=np.sum(v*q,axis=1)*inv
 mask=valid&(u>=-1e-7)&(w>=-1e-7)&(u+w<=1.0000001)&(dist>1e-6)
 return (dist[mask],np.flatnonzero(mask)) if indices else dist[mask]

def reject(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('fault escaped')

def glass(t,f):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);n/=np.linalg.norm(n,axis=1)[:,None]
 ids=np.flatnonzero(((f&2)>0)&(((abs(n[:,1])>.9999)&(n[:,1]*t.mean(axis=1)[:,1]>0)&(abs(t.mean(axis=1)[:,1])>1.4))|((n[:,0]>.95)&(t.mean(axis=1)[:,0]>9.7))))
 assert len(ids)>10,'missing actual glazing'
 for i in ids[::max(1,len(ids)//80)]:
  p=t[i].mean(axis=0)
  # Wipers occupy tiny regions, exclude only ray paths near the actual wiper
  # line: other triangles and the middle glazing receive no exemption.
  if p[0]>9.7 and .9<abs(p[1])<1.06 and 2.2<p[2]<2.9:continue
  ds=ray(t,p+n[i]*.2,-n[i]);assert len(ds) and min(ds)>.197,('glass buried / occluded',i,p.tolist(),min(ds) if len(ds) else None)
  other=t[(f&2)==0]
  ds=ray(other,p-n[i]*.0001,-n[i]);assert len(ds) and min(ds)<.055,('glass floating / unsupported',i,p.tolist(),min(ds) if len(ds) else None)
 return ids,n

def wheels(t):
 for x in [-8.05,-5.25,5.25,8.05]:
  for y in [-.615,.615]:
   sel=(abs(t[:,:,0]-x)<.431).all(axis=1)&(abs(t[:,:,1]-y)<.091).all(axis=1)&(t[:,:,2]<.861).all(axis=1)
   points=t[sel].reshape(-1,3);assert len(points)>10,'wheel missing'
   assert abs(points[:,2].min())<1e-5 and abs(points[:,2].max()-.86)<1e-5,'wheel off rail'
   ds=ray(t,np.array([x,y,.865]),np.array([0.,0.,1.]));assert len(ds) and min(ds)>.01,'wheel clearance'

def roof(t):
 for x in [-7.8,7.8]:
  sel=(abs(t[:,:,0]-x)<1.301).all(axis=1)&(abs(t[:,:,1])<.876).all(axis=1)&(t[:,:,2]>3.6499).all(axis=1)&(t[:,:,2]<3.9651).all(axis=1)
  p=t[sel].reshape(-1,3);assert len(p)>10 and abs(p[:,2].min()-3.65)<1e-4,'AC floating'
  assert abs(p[:,0].min()-(x-1.3))<1e-4 and abs(p[:,0].max()-(x+1.3))<1e-4,'AC position'
  ds=ray(t[~sel],np.array([x,0,3.651]),np.array([0.,0.,-1.]));assert len(ds) and min(ds)<.002,'no roof support'
 return sel

def layout(t,f,role):
 # Rebuilt centre glazing must replace the old door leaves, not hide them.
 if role!='ep':
  sel=((f&2)>0)&(abs(t[:,:,0])<.7).all(axis=1)&(abs(t[:,:,1])>1.4).all(axis=1)
  p=t[sel].reshape(-1,3);assert len(p)>10 and p[:,2].min()<1.4 and p[:,2].max()>2.9,'former centre door not converted'
  # There must be no retained door-leaf glazing at x +/- .323, z2.3-2.95.
  # Check the actual planar surface layer count through the new centre pane.
  for side in [-1,1]:
   ds=sorted(ray(t,np.array([.323,side*1.7,2.6]),np.array([0.,-side,0.])))
   local=[v for v in ds if v<.3]
   unique=[]
   for v in local:
    if not unique or abs(v-unique[-1])>1e-4:unique.append(v)
   assert len(unique)<=4,'duplicate old centre surfaces'
 if role in ['emc','em']:
  # The old raised walk-through portal must be gone: sealed nose below glass.
  ds=ray(t,np.array([10.5,0,1.7]),np.array([-1.,0.,0.]))
  assert len(ds) and .48<min(ds)<.57,'portal / internal plate pierces nose'


def colors(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 return np.array([struct.unpack_from('<I',b,o+i*52+16)[0] for i in range(n)],dtype=np.uint32)

def lod(near,far,nc,fc):
 for x in [-9,-4,-2,2,4,9]:
  for z in [1.4,2,3.15]:
   for side in [-1,1]:
    o=np.array([x,side*2.,z]);d=np.array([0.,-side,0.]);a,ai=ray(near,o,d,True);b,bi=ray(far,o,d,True)
    assert len(a) and len(b) and abs(min(a)-min(b))<.04,'LOD contour shift'
    ca=nc[ai[np.argmin(a)]];cb=fc[bi[np.argmin(b)]]
    assert max(abs(int((ca>>s)&255)-int((cb>>s)&255)) for s in [0,8,16])<=40,'LOD paint jump'
