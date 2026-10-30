"""New Taipei output probes (ray reader adapted from Codex KLRT cfeed799). Display constraints, not engineering/complete collision proof."""
import json,struct,sys,copy
from pathlib import Path
import numpy as np

def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 return np.array([[struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)] for i in range(n)]),np.array([struct.unpack_from('<I',b,o+i*52)[0] for i in range(n)])

def ray(t,o,d,indices=False):
 e=t[:,1]-t[:,0];v=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,v.shape),v);a=np.sum(e*h,axis=1);valid=abs(a)>1e-10
 inv=np.divide(1,a,out=np.zeros_like(a),where=valid);s=o-t[:,0];u=np.sum(s*h,axis=1)*inv;q=np.cross(s,e);w=np.sum(q*d,axis=1)*inv;dist=np.sum(v*q,axis=1)*inv
 mask=valid&(u>=-1e-7)&(w>=-1e-7)&(u+w<=1.0000001)&(dist>1e-6)
 return (dist[mask],np.flatnonzero(mask)) if indices else dist[mask]

def colors(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 return np.array([struct.unpack_from('<I',b,o+i*52+16)[0] for i in range(n)],dtype=np.uint32)

def actual_wiper(t,f):
 # The isolated 18mm beam is an expected foreground occluder. Derive its
 # connected triangles from actual geometry; never excuse a whole glass region.
 parent=list(range(len(t)));seen={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 candidates=np.flatnonzero((t[:,:,0]>3.4).all(axis=1)&(abs(t[:,:,1])<.5).all(axis=1)&(t[:,:,2]>1.10).all(axis=1)&(t[:,:,2]<2.10).all(axis=1))
 for i in candidates:
  for point in t[i]:
   key=tuple(np.round(point,5))
   if key in seen:parent[find(i)]=find(seen[key])
   else:seen[key]=i
 groups={}
 for i in candidates:groups.setdefault(find(i),[]).append(i)
 out=np.zeros(len(t),dtype=bool)
 for ids in groups.values():
  if len(ids)!=12 or np.any(f[ids]&2):continue
  p=t[ids].reshape(-1,3);lo=p.min(axis=0);hi=p.max(axis=0)
  volume=abs(np.sum(np.einsum("ij,ij->i",t[ids,0],np.cross(t[ids,1],t[ids,2])))/6)
  if volume<.001 and lo[0]>3.4 and max(abs(lo[1]),abs(hi[1]))<.5 and lo[2]>1.10 and hi[2]<2.10 and hi[2]-lo[2]>.85 and hi[1]-lo[1]>.60:out[ids]=True
 return out

def glass(t,f):
 # Backing may be the adjoining frame closer than the nominal 24/25mm shell
 # thickness. Require a real inward-facing hit within35mm, not a false minimum
 # distance that rejects this valid contact. Visibility is checked separately.
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);n/=np.linalg.norm(n,axis=1)[:,None];c=t.mean(axis=1)
 visible=t[~actual_wiper(t,f)]
 ids=np.flatnonzero((f&2)>0);assert len(ids)>=4,'no real glass'
 for i in ids[::max(1,len(ids)//96)]:
  for weights in [[1/3]*3,[.6,.2,.2]]:
   p=np.array(weights)@t[i]
   ds=ray(visible,p+n[i]*.20,-n[i]);assert len(ds) and min(ds)>.197,'glass occluded/buried'
   backing=((f&2)==0)&(np.sum(n*n[i],axis=1)<-.70)
   ds=ray(t[backing],p-n[i]*.0001,-n[i]);assert len(ds) and min(ds)<.035,'glass lost backing / floating'
 return ids,n,c


def reject(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('actual geometry mutation escaped')

ROLES=['m1','m2','m3','m4','m5'];XS=[13.225,5.725,0,-5.725,-13.225]
LENGTHS=[8,6,4.45,6,8]
def wheelcheck(t,role):
 if role in ['m2','m4']:
  assert t[:,:,2].min()>=.249,'invented wheel on suspended unit';return
 bx=-1.55 if role in ['m1','m5'] else 0
 for x in [bx-.83,bx+.83]:
  for y in [-.7175,.7175]:
   sel=(abs(t[:,:,0]-x)<.2901).all(axis=1)&(abs(t[:,:,1]-y)<.056).all(axis=1)&(t[:,:,2]<.581).all(axis=1)
   p=t[sel].reshape(-1,3);assert len(p)>12,'wheel missing'
   assert abs(p[:,2].min())<1e-5 and abs(p[:,2].max()-.58)<1e-5,'wheel off rail'
   ds=ray(t,np.array([x,y,.585]),np.array([0.,0.,1.]));assert len(ds) and min(ds)>.055,'wheel clearance'

def roofcheck(t,role):
 x,length,width,height=(-.5,3.1,1.63,.27) if role in ['m1','m5'] else (0,4.85,1.66,.14) if role in ['m2','m4'] else (0,2.7,1.38,.11)
 sel=(abs(t[:,:,0]-x)<length/2+.001).all(axis=1)&(abs(t[:,:,1])<width/2+.001).all(axis=1)&(t[:,:,2]>=3.34999).all(axis=1)&(t[:,:,2]<=3.35+height+.0001).all(axis=1)
 p=t[sel].reshape(-1,3);assert len(p)>0,'roof equipment missing'
 assert abs(p[:,2].min()-3.35)<.0001,'equipment floating'
 assert abs(p[:,0].min()-(x-length/2))<.001 and abs(p[:,0].max()-(x+length/2))<.001,'equipment position'
 ds=ray(t[~sel],np.array([x,0,3.351]),np.array([0.,0.,-1.]));assert len(ds) and min(ds)<.002,'roof contact missing'
 return sel

def formation(s,fleet,far,root):
 suffix='-far' if far else ''
 assert [p['unit'] for p in s['placements']]==[fleet+'-lrt-'+r+suffix for r in ROLES],'wrong order'
 assert [p['rotation_degrees'] for p in s['placements']]==[0,0,0,0,180],'wrong direction'
 assert [p['translation'] for p in s['placements']]==[[x,0,0]for x in XS],'wrong position'
 import base64
 ts=[]
 for p in s['placements']:
  b=(root/'models'/(p['unit']+'.m3dmodel')).read_bytes();assert base64.b64decode(s['units'][p['unit']])==b,'stale assembly'
  t,f=read(root/'models'/(p['unit']+'.m3dmodel'))
  if p['rotation_degrees']==180:t[:,:,:2]*=-1
  ts.extend(t+np.array(p['translation']))
 t=np.array(ts)
 assert abs(np.ptp(t[:,:,0])-34.45)<.0001 and abs(t[:,:,2].min())<.00001
 for i in range(4):
  x=(XS[i]-LENGTHS[i]/2+XS[i+1]+LENGTHS[i+1]/2)/2
  for side in [-1,1]:
   ds=ray(t,np.array([x,side*1.6,1.8]),np.array([0.,-side,0.]));assert len(ds) and min(ds)<.40,'joint gap'
  ds=ray(t,np.array([x,0,1.8]),np.array([1.,0.,0.]));assert not len(ds) or min(ds)>2,'fictional passenger end wall'
 return t

root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());fleet=m['models'][0]['id'].split('-')[0];rows=[]
for r in m['models']:
 if r.get('native_kind')=='assembly':
  s=json.loads((root/r['native']).read_text());far=r['id'].endswith('-far');t=formation(s,fleet,far,root)
  for mode in ['order','rotation','translation']:
   b=copy.deepcopy(s)
   if mode=='order':b['placements'][0]['unit'],b['placements'][1]['unit']=b['placements'][1]['unit'],b['placements'][0]['unit']
   elif mode=='rotation':b['placements'][4]['rotation_degrees']=0
   else:b['placements'][2]['translation'][0]+=.10
   reject(lambda:formation(b,fleet,far,root))
  rows.append({'id':r['id'],'actual_five_unit_assembly_open_passage_joints_common_rail':True,'order_direction_displacement_mutations_rejected':True});continue
 t,f=read(root/r['native']);role=r['id'].split('-')[2]
 ids,n,c=glass(t,f);wheelcheck(t,role);eq=roofcheck(t,role)
 # Mutate the actual outward-facing side glass, keeping backing in place.
 pane=ids[(n[ids,1]>.95)&(c[ids,0]<0)]
 assert len(pane)>0
 for amount in [-.08,.08]:
  bad=t.copy();bad[pane,:,1]+=amount;reject(lambda:glass(bad,f))
 if role not in ['m2','m4']:
  bx=-1.55 if role in ['m1','m5'] else 0
  sel=(abs(t[:,:,0]-(bx-.83))<.291).all(axis=1)&(abs(t[:,:,1]-.7175)<.056).all(axis=1)&(t[:,:,2]<.581).all(axis=1)
  bad=t.copy();bad[sel,:,2]+=.035;reject(lambda:wheelcheck(bad,role))
 for axis,amount in [(2,.08),(0,.15)]:
  bad=t.copy();bad[eq,:,axis]+=amount;reject(lambda:roofcheck(bad,role))
 rows.append({'id':r['id'],'sampled_glass_visibility_and_backing':True,'buried_floated_glass_80mm_rejected':True,'wheel_or_suspension_and_clearance':True,'wheel_35mm_and_equipment_80mm_150mm_mutations_rejected':True})
byid={r['id']:r for r in m['models']}
for role in ROLES:
 a=byid[f'{fleet}-lrt-{role}'];b=byid[a['id']+'-far']
 assert b['triangles']*2<a['triangles'],'far not below half'
 for field in ['minimum','maximum']:assert max(abs(x-y)for x,y in zip(a[field],b[field]))<.015,'LOD bounds jump'
 assert a['triangles']<=15000 and b['triangles']<=15000
# Sealed plate solids alone cannot detect a gap between front and shoulder.
# Derive the reference edge from actual near vertices, then ray-test both LODs.
def shoulder(near,other):
 skin=near[(near[:,:,1]>1.32).all(axis=1)]
 for height in [.80,1.0,1.18,1.4,2.0,2.6,2.9]:
  crossings=[]
  for j in range(3):
   a,b=skin[:,j],skin[:,(j+1)%3]
   mask=(((a[:,2]<=height)&(b[:,2]>=height))|((b[:,2]<=height)&(a[:,2]>=height)))&(abs(a[:,2]-b[:,2])>1e-7)
   ratio=(height-a[mask,2])/(b[mask,2]-a[mask,2]);crossings.extend((a[mask]+(b[mask]-a[mask])*ratio[:,None])[:,0])
  assert crossings,'missing shoulder reference'
  origin=np.array([max(crossings)-.07,1.60,height])
  ds=ray(other,origin,np.array([0.,-1.,0.]));assert len(ds) and min(ds)<.30,'daylight gap at cab shoulder'
for role in ['m1','m5']:
 near,_=read(root/'models'/f'{fleet}-lrt-{role}.m3dmodel');far,_=read(root/'models'/f'{fleet}-lrt-{role}-far.m3dmodel')
 shoulder(near,near);shoulder(near,far)
 broken=far.copy();sel=(broken[:,:,1]>1.30).all(axis=1)&(broken[:,:,0]>2).all(axis=1);broken[sel,:,0]-=.20
 reject(lambda:shoulder(near,broken))
(root/'fleet-verification.json').write_text(json.dumps({'status':'VERIFIED','models':rows,'limits':['Sampled rays, not exhaustive self intersection proof','Module lengths, bogie wheel dimensions and hidden equipment are photo estimates','Static assembly only; no curve, grade, articulation animation or device verification']},indent=2)+'\n')
print('VERIFIED',fleet,'12 native units/assemblies; actual fault mutations rejected')
