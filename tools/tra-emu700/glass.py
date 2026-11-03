"""EMU700 actual glass-solid centroid rays. Read/normal/ray/component methods
adapted from main a4dddd40 tools/taoyuan-airport/audit.py; thresholds here use
this vehicle's native dimensions. Not all-surface collision certification."""
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
def glazing(t,f,required=None):
 n=normals(t);c=t.mean(axis=1);sel=((f&2)!=0)&(((abs(c[:,1])>1.44)&(n[:,1]*c[:,1]>1))|((n[:,0]*c[:,0]>7)&(abs(c[:,0])>8.7)&(abs(c[:,1])<1.3)))
 ids=np.flatnonzero(sel) if required is None else required;assert len(ids)>0,'missing glass'
 # Exclude only the two actual thin wiper solids from the visibility rays,
 # rather than exempting a large part of the windshield.
 ignored=[]
 for g in components(t):
  lo=t[g].reshape(-1,3).min(axis=0);hi=t[g].reshape(-1,3).max(axis=0);size=hi-lo
  if len(g)==12 and lo[0]>9.4 and 2.37<lo[2]<2.42 and 2.58<hi[2]<2.62 and .30<size[1]<.34 and .19<size[2]<.23 and size[0]<.20:ignored.extend(g)
 visible=np.ones(len(t),dtype=bool);visible[ignored]=False
 support=(f&2)==0
 # Downward backs of glass solids are unmarked by the shared material rule;
 # exclude their whole connected solids so they cannot support themselves.
 for g in components(t):
  if np.any((f[g]&2)!=0):support[g]=False
 for i in ids:
  ds=hits(t[visible],c[i]+n[i]*.30,-n[i]);assert len(ds) and min(ds)>.297,('glass occluded',int(i),c[i].tolist(),float(min(ds)) if len(ds) else None)
  # Interior support within 45mm: this recipe has at most 42mm of panel
  # offset/layer stack, plus 3mm sampling tolerance; not a prototype limit.
  ds=hits(t[support],c[i]-n[i]*.001,-n[i]);assert len(ds) and min(ds)<.045,('glass floats',i,c[i].tolist(),float(min(ds)) if len(ds) else None)
 return ids

def components(t):
 parent=list(range(len(t)));edge={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 points=np.rint(t*1e5).astype(np.int64)
 for i,tri in enumerate(points):
  keys=[tuple(p) for p in tri]
  for j in range(3):
   k=tuple(sorted((keys[j],keys[(j+1)%3])))
   if k in edge:parent[find(i)]=find(edge[k])
   else:edge[k]=i
 groups={}
 for i in range(len(t)):groups.setdefault(find(i),[]).append(i)
 return [np.array(v,dtype=int) for v in groups.values()]

def equipment(t,role):
 groups=components(t);ac=[]
 for g in groups:
  lo=t[g].reshape(-1,3).min(axis=0);hi=t[g].reshape(-1,3).max(axis=0)
  if np.max(np.abs((hi-lo)-np.array([3.1,1.84,.25])))<.001:ac.append((g,lo,hi))
 assert len(ac)==2,'missing or duplicated AC shell'
 expected=[-6.45,3.4] if role=='ep' else [-6.45,6.45]
 centers=sorted(float((lo[0]+hi[0])/2) for _,lo,hi in ac)
 assert np.max(np.abs(np.array(centers)-expected))<.001,'AC station'
 for g,lo,hi in ac:
  assert len(g)==12,'duplicate AC geometry'
  assert abs(lo[2]-3.7)<.0001,'AC floats'
  center=(lo+hi)/2;support=np.ones(len(t),dtype=bool)
  for gg,_,_ in ac:support[gg]=False
  ray=hits(t[support],np.array([center[0],0,3.71]),np.array([0.,0,-1.]))
  assert len(ray) and min(ray)<.012,'AC roof contact'
 high=t.reshape(-1,3);high=high[high[:,2]>4.1]
 if role=='ep':
  assert len(high)>0 and high[:,0].min()>7.1 and high[:,0].max()<8.9,'pantograph absent or wrong station'
  knee=high[(high[:,2]>4.40)&(high[:,2]<4.46)];top=high[high[:,2]>4.91]
  assert len(knee) and len(top) and knee[:,0].max()>8.7 and abs(top[:,0].mean()-7.75)<.05,'pantograph reversed' 
 else:assert not len(high),'unexpected pantograph'
 return ac

def underfloor(t,role):
 groups=components(t);cases=[]
 for g in groups:
  lo=t[g].reshape(-1,3).min(axis=0);hi=t[g].reshape(-1,3).max(axis=0)
  if np.max(np.abs((hi-lo)-np.array([1.35,1.60,.50])))<.001:cases.append((g,lo,hi))
 expected={'ep':[-3.7,-.8,2.3],'et':[-3.7,-1.6,1.,3.4]}.get(role,[-3.6,-1.1,1.5,3.5])
 assert len(cases)==len(expected),'underfloor case missing'
 centers=sorted(float((lo[0]+hi[0])/2) for _,lo,hi in cases)
 assert np.max(np.abs(np.array(centers)-expected))<.001,'underfloor case station'
 support=np.ones(len(t),dtype=bool)
 for g,_,_ in cases:support[g]=False
 for g,lo,hi in cases:
  assert len(g)==12 and abs(hi[2]-.98)<.0001,'underfloor floats or duplicated'
  ds=hits(t[support],np.array([(lo[0]+hi[0])/2,0,.979]),np.array([0.,0,1.]))
  assert len(ds) and min(ds)<.003,'underfloor chassis contact'
 return cases

def coupler(t):
 end=20.743/2
 # Ordinary service photographs show a continuous closed FRP front, not
 # the previous square frontal jaw. Its real cavity is accessed from below.
 ds=hits(t,np.array([end+.12,0,.92]),np.array([-1.,0,0]))
 assert len(ds) and .15<min(ds)<.36,'normal nose cover absent'
 under=hits(t,np.array([end-.36,0,.40]),np.array([0.,0,1.]))
 assert len(under) and .30<min(under)<.50,'underside coupler cavity blocked'
 return True

def reject(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('actual equipment fault escaped')

root=Path(sys.argv[1]);rows=[]
for m in json.loads((root/'manifest.json').read_text())['models']:
 if m.get('native_kind')=='assembly':continue
 t,f=read(root/m['native']);role=m['id'].split('-')[2];ac=equipment(t,role)
 cases=underfloor(t,role);g=cases[0][0];broken=t.copy();broken[g,:,2]-=.1;reject(lambda:underfloor(broken,role))
 broken=t.copy();broken[g,:,0]+=.3;reject(lambda:underfloor(broken,role))
 reject(lambda:underfloor(np.concatenate([t,t[g]]),role))

 if role=='emc':
  coupler(t);bars=[]
  for g in components(t):
   lo=t[g].reshape(-1,3).min(axis=0);hi=t[g].reshape(-1,3).max(axis=0)
   if np.max(np.abs((hi-lo)-np.array([.16,.48,.32])))<.001 and abs(lo[2]-.76)<.001:bars.append(g)
  assert len(bars)==1,'coupler upper jaw identity'
  broken=t.copy();g=bars[0];local=broken[g].copy();local[:,:,2][np.isclose(local[:,:,2],.76,atol=.0001)]=.55;broken[g]=local
  reject(lambda:coupler(broken))

 g=ac[0][0];broken=t.copy();broken[g,:,2]+=.10;reject(lambda:equipment(broken,role))
 broken=t.copy();broken[g,:,0]+=.30;reject(lambda:equipment(broken,role))
 reject(lambda:equipment(np.concatenate([t,t[g]]),role))
 if role=='ep':
  pant=[g for g in components(t) if t[g,:,2].max()>4.1]
  mask=np.ones(len(t),dtype=bool)
  for g in pant:mask[g]=False
  reject(lambda:equipment(t[mask],role))
  broken=t.copy()
  for g in pant:broken[g,:,0]-=3
  reject(lambda:equipment(broken,role))
  reversed_pant=t.copy()
  for g in pant:
   reversed_pant[g,:,0]=16-reversed_pant[g,:,0];reversed_pant[g,:,1]*=-1
  reject(lambda:equipment(reversed_pant,role))
 ids=glazing(t,f);groups=components(t);tested=[]
 for g in groups:
  chosen=np.intersect1d(g,ids)
  if not len(chosen):continue
  direction=normals(t)[chosen].mean(axis=0);direction/=np.linalg.norm(direction)
  for distance in [-.20,.20]:
   broken=t.copy();broken[g]+=direction*distance
   try:glazing(broken,f,ids)
   except AssertionError:pass
   else:raise AssertionError(('actual glass solid fault escaped',m['id'],distance,'group',len(g),'chosen',len(chosen),'direction',direction.tolist(),'bounds',t[g].reshape(-1,3).min(axis=0).tolist(),t[g].reshape(-1,3).max(axis=0).tolist()))
  tested.append(len(g))
 rows.append({'id':m['id'],'closed_cover_underside_cavity_and_actual_blocked_bar_fault':role=='emc','underfloor_contact_and_three_actual_faults':True,'ac_contact_and_three_actual_faults':True,'ep_missing_and_wrong_station_faults':role=='ep','front_centroid_samples':len(ids),'glass_solids_tested':len(tested),'buried_200mm_rejected':True,'floating_200mm_rejected':True})
(root/'glass-verification.json').write_text(json.dumps({'status':'VERIFIED','models':rows,'limits':'Centroid rays on outward side and cab/end glass faces, and actual connected glass solid displacement; no exhaustive surface or engineering collision proof.'},indent=2)+'\n')
print('VERIFIED',len(rows),'units: visible supported glass and connected-solid displacement faults')
