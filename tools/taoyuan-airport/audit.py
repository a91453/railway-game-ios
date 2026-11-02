#!/usr/bin/env python3
"""Actual-triangle probes; centroid rays are not exhaustive collision proof.
Read/normal/ray primitives adapted from main 39aaec02 tools/taichung-green/audit.py.
Only this vehicle's dimensions and fault probes are used.
"""
import json,sys,struct
from pathlib import Path
import numpy as np

def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 t=[];f=[]
 for i in range(n):
  f.append(struct.unpack_from('<I',b,o+i*52)[0]);t.append([struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)])
 return np.array(t),np.array(f)
def normals(t):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);return n/np.linalg.norm(n,axis=1)[:,None]
def hits(t,o,d):
 e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,e2.shape),e2);a=np.sum(e1*h,axis=1);ok=np.abs(a)>1e-9
 inv=np.divide(1,a,out=np.zeros_like(a),where=ok);s=o-t[:,0];u=inv*np.sum(s*h,axis=1);q=np.cross(s,e1);v=inv*np.sum(d*q,axis=1);dist=inv*np.sum(e2*q,axis=1)
 return dist[ok&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1+1e-6)&(dist>1e-6)]
def glazing(t,f):
 n=normals(t);c=t.mean(axis=1);sel=((f&2)!=0)&(((abs(c[:,1])>1.52)&(n[:,1]*c[:,1]>1))|((n[:,0]>.8)&(c[:,0]>9)))
 ids=np.flatnonzero(sel);assert len(ids)>0,'missing glass'
 for i in ids:
  ds=hits(t,c[i]+n[i]*.30,-n[i]);assert len(ds) and min(ds)>.297,'glass occluded'
  # Interior support within 65mm of actual glass front, excluding glass itself.
  ds=hits(t[(f&2)==0],c[i]-n[i]*.001,-n[i]);assert len(ds) and min(ds)<.065,('glass floats',i,c[i].tolist(),float(min(ds)) if len(ds) else None)
 return ids

def wheels(t):
 p=t.reshape(-1,3)
 for x in [-7.8,-5.7,5.7,7.8]:
  for y in [-.7675,.7675]:
   q=p[(abs(p[:,0]-x)<.426)&(abs(p[:,1]-y)<.051)&(p[:,2]<.851)]
   assert len(q)>10 and abs(q[:,2].min())<1e-5,'missing/lifted wheel'
   ds=hits(t,np.array([x,y,.86]),np.array([0.,0,1.]));assert len(ds) and min(ds)>.05,'tyre body clearance'
def roof(t,baggage):
 p=t.reshape(-1,3)
 for x in ([8.05] if baggage else [-6.25,6.25]):
  q=p[(abs(p[:,0]-x)<1.7)&(abs(p[:,1])<.7)&(p[:,2]>3.76)]
  assert len(q) and abs(q[:,2].min()-3.763)<.001,'HVAC lifted'
  ds=hits(t[t[:,:,2].max(axis=1)<3.764],np.array([x,0,3.77]),np.array([0.,0,-1.]));assert len(ds) and min(ds)<.01,'roof support missing'
def rejected(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('fault escaped')
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for m in manifest['models']:
 if m.get('native_kind')=='assembly':continue
 t,f=read(root/m['native']);ids=glazing(t,f);wheels(t);roof(t,'-dmb' in m['id'])
 q=t.copy();q[ids]-=normals(t)[ids,None,:]*.15;rejected(lambda:glazing(q,f))
 q=t.copy();q[ids]+=normals(t)[ids,None,:]*.15;rejected(lambda:glazing(q,f))
 q=t.copy();mask=(q[:,:,2].max(axis=1)<.851);q[mask,:,2]+=.04;rejected(lambda:wheels(q))
 q=t.copy();mask=(q[:,:,2].min(axis=1)>=3.763-.00001);q[mask,:,2]+=.08;rejected(lambda:roof(q,'-dmb' in m['id']))
 rows.append({'id':m['id'],'glass_samples':len(ids),'eight_wheels':True,'roof_support':True,'four_faults_rejected':True})
def formation(spec, fleet, far):
 suffix='-far' if far else ''
 roles=['dmc1','mc1','mc2','dmc2'] if fleet=='1000' else ['dme1','me1','me3','me4','dmb']
 expected=['taoyuan-airport-'+r+suffix for r in roles]
 assert [x['unit'] for x in spec['placements']]==expected,'missing baggage/wrong role/order'
 assert [x['rotation_degrees'] for x in spec['placements']]==[0]*(len(roles)-1)+[180],'direction/double reversal'
 lengths=[20.78 if r in ['dmc1','dmc2','dme1','dmb'] else 20.25 for r in roles];cursor=sum(lengths)/2
 for p,length in zip(spec['placements'],lengths):
  x=cursor-length/2;cursor-=length
  assert np.max(np.abs(np.array(p['translation'])-[x,0,0]))<1e-5,'wrong placement'
for m in manifest['models']:
 if m.get('native_kind')!='assembly':continue
 fleet='1000' if '1000' in m['id'] else '2000';far=m['id'].endswith('-far')
 spec=json.loads((root/m['native']).read_text());formation(spec,fleet,far)
 import copy
 q=copy.deepcopy(spec);q['placements'].pop();rejected(lambda:formation(q,fleet,far))
 q=copy.deepcopy(spec);q['placements'][-1]['rotation_degrees']=0;rejected(lambda:formation(q,fleet,far))
 q=copy.deepcopy(spec);q['placements'][0]['translation'][0]+=.1;rejected(lambda:formation(q,fleet,far))
 q=copy.deepcopy(spec);q['placements'][0],q['placements'][1]=q['placements'][1],q['placements'][0];rejected(lambda:formation(q,fleet,far))
(root/'taoyuan-verification.json').write_text(json.dumps({'status':'VERIFIED','models':rows,'limits':'centroid visibility/support rays, eight tyre envelopes and roof central support only; not exhaustive self-intersection proof'},indent=2)+'\n')
print('VERIFIED',len(rows),'units and four actual-geometry fault examples each')
