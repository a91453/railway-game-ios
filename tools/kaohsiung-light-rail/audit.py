"""KLRT output probes. Display constraints, not engineering/complete collision proof."""
import json,struct,sys,copy
from pathlib import Path
import numpy as np

def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 return np.array([[struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)] for i in range(n)]),np.array([struct.unpack_from('<I',b,o+i*52)[0] for i in range(n)])

def ray(t,o,d):
 e=t[:,1]-t[:,0];v=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,v.shape),v);a=np.sum(e*h,axis=1);valid=abs(a)>1e-10
 inv=np.divide(1,a,out=np.zeros_like(a),where=valid);s=o-t[:,0];u=np.sum(s*h,axis=1)*inv;q=np.cross(s,e);w=np.sum(q*d,axis=1)*inv;dist=np.sum(v*q,axis=1)*inv
 return dist[valid&(u>=-1e-7)&(w>=-1e-7)&(u+w<=1.0000001)&(dist>1e-6)]

def glass(t,f):
 # Backing may be the adjoining frame closer than the nominal 24/25mm shell
 # thickness. Require a real inward-facing hit within35mm, not a false minimum
 # distance that rejects this valid contact. Visibility is checked separately.
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);n/=np.linalg.norm(n,axis=1)[:,None];c=t.mean(axis=1)
 ids=np.flatnonzero((f&2)>0);assert len(ids)>8,'no real glass'
 for i in ids:
  for weights in [[1/3]*3,[.6,.2,.2]]:
   p=np.array(weights)@t[i]
   ds=ray(t,p+n[i]*.20,-n[i]);assert len(ds) and min(ds)>.197,'glass occluded/buried'
   backing=((f&2)==0)&(np.sum(n*n[i],axis=1)<-.70)
   ds=ray(t[backing],p-n[i]*.0001,-n[i]);assert len(ds) and min(ds)<.035,'glass lost backing / floating'
 return ids,n,c

def wheels(t,fleet,role):
 sc=role in ['s1','s2','sc1','sc2'];r=.30 if fleet=='caf' else .295
 if sc:
  assert t[:,:,2].min()>.17,'invented running gear under suspended module';return
 centre=(-1.65 if fleet=='caf' else -1.73) if role in ['c1','c2','m1','m2'] else 0
 halfbase=.90 if fleet=='caf' else .80
 for x in [centre-halfbase,centre+halfbase]:
  for y in [-.7175,.7175]:
   sel=(abs(t[:,:,0]-x)<r+.001).all(axis=1)&(abs(t[:,:,1]-y)<.056).all(axis=1)&(t[:,:,2]<2*r+.001).all(axis=1)
   p=t[sel].reshape(-1,3);assert len(p)>=24,'missing wheel'
   assert abs(p[:,2].min())<1e-5 and abs(p[:,2].max()-2*r)<1e-5,'wheel not on rail / wrong diameter'
   ds=ray(t,np.array([x,y,2*r+.005]),np.array([0.,0.,1.]));assert len(ds) and min(ds)>.075,'wheel/floor clearance'

def equipment(t,fleet,role):
 roof=3.15 if fleet=='caf' else 3.20
 if fleet=='caf':
  x,length,width,height=(-1.34,3.211,1.845,.45) if role in ['c1','c2'] else (.30,2.92,1.63,.30) if role in ['s1','s2'] else (-.72,.90,1.48,.31)
 else:
  x,length,width,height=(-1.40,2.30,1.58,.24) if role in ['m1','m2'] else ((-.80 if role=='sc1' else .80),2.53,1.72,.40) if role in ['sc1','sc2'] else (-.18,2.40,1.22,.07)
 sel=(abs(t[:,:,0]-x)<length/2+.001).all(axis=1)&(abs(t[:,:,1])<width/2+.001).all(axis=1)&(t[:,:,2]>=roof-.0001).all(axis=1)
 assert sel.any(),'roof housing absent'
 p=t[sel].reshape(-1,3)
 assert abs(p[:,0].min()-(x-length/2))<.002 and abs(p[:,0].max()-(x+length/2))<.002,'housing position/length jumped'
 base=t[sel,:,2].min();assert abs(base-roof)<1e-4,'housing floated'
 ds=ray(t[~sel],np.array([x,0,base+.01]),np.array([0.,0.,-1.]));assert len(ds) and min(ds)<.011,'housing not supported on real roof'
 return sel

CONTRACTS={
 'caf':(['c1','s1','r','s2','c2'],[13.1915,5.65,0,-5.65,-13.1915],[7.783,6.10,4.,6.10,7.783],34.166),
 'citadis':(['m1','sc1','np','sc2','m2'],[12.775,5.325,0,-5.325,-12.775],[7.85,5.85,3.6,5.85,7.85],33.4)}

def assembly(s,fleet,far,root):
 roles,xs,lengths,total=CONTRACTS[fleet];suffix='-far' if far else ''
 assert [p['unit'] for p in s['placements']]==['klrt-'+fleet+'-'+r+suffix for r in roles],'module sequence wrong'
 assert [p['rotation_degrees'] for p in s['placements']]==[0,0,0,0,180],'module direction wrong'
 assert [p['translation'] for p in s['placements']]==[[x,0,0] for x in xs],'joint datum wrong'
 import base64
 triangles=[]
 for p in s['placements']:
  b=base64.b64decode(s['units'][p['unit']]);assert b==(root/'models'/(p['unit']+'.m3dmodel')).read_bytes(),'assembly embeds stale unit'
  t,f=read(root/'models'/(p['unit']+'.m3dmodel'))
  if p['rotation_degrees']==180:t[:,:,:2]*=-1
  t+=p['translation'];triangles.extend(t)
 t=np.array(triangles);assert abs(np.ptp(t[:,:,0])-total)<1e-4,'whole-set physical length'
 assert abs(t[:,:,2].min())<1e-5,'assembly rail datum'
 # Four real flexible joints bridge the actual 600mm gaps, no coupler boxes.
 for i in range(4):
  edge=xs[i]-lengths[i]/2;other=xs[i+1]+lengths[i+1]/2
  assert abs(edge-other-.6)<1e-5
  mid=(edge+other)/2
  for side in [-1,1]:
   ds=ray(t,np.array([mid,side*1.5,1.70]),np.array([0.,-side,0.]));assert len(ds) and min(ds)<.32,'open/misaligned joint'
 return t

def rejected(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('real geometry mutation escaped')

root=Path(sys.argv[1]);m=json.loads((root/'manifest.json').read_text());fleet='caf' if m['models'][0]['id'].startswith('klrt-caf-') else 'citadis';rows=[]
for r in m['models']:
 if r.get('native_kind')=='assembly':
  s=json.loads((root/r['native']).read_text());far=r['id'].endswith('-far');t=assembly(s,fleet,far,root)
  for mode in ['order','rotation','translation']:
   b=copy.deepcopy(s)
   if mode=='order':b['placements'][0]['unit'],b['placements'][1]['unit']=b['placements'][1]['unit'],b['placements'][0]['unit']
   elif mode=='rotation':b['placements'][4]['rotation_degrees']=0
   else:b['placements'][2]['translation'][0]+=.10
   rejected(lambda:assembly(b,fleet,far,root))
  rows.append({'id':r['id'],'five_units_order_orientation_actual_joints_common_rail':True,'wrong_order_rotation_and_100mm_displacement_rejected':True});continue
 t,f=read(root/r['native']);role=r['id'].split('-')[2]
 ids,n,c=glass(t,f);wheels(t,fleet,role);eq=equipment(t,fleet,role)
 # Actual window faces in the delivered output. White inner support stays put.
 pane=ids[(n[ids,1]>.95)&(c[ids,0]<0)]
 assert len(pane)>0
 for amount in [-.08,.08]:
  broken=t.copy();broken[pane,:,1]+=amount;rejected(lambda:glass(broken,f))
 if role not in ['s1','s2','sc1','sc2']:
  rad=.3 if fleet=='caf' else .295;centre=(-1.65 if fleet=='caf' else -1.73) if role in ['c1','c2','m1','m2'] else 0;dx=.9 if fleet=='caf' else .8
  sel=(abs(t[:,:,0]-(centre-dx))<rad+.001).all(axis=1)&(abs(t[:,:,1]-.7175)<.056).all(axis=1)&(t[:,:,2]<2*rad+.001).all(axis=1)
  broken=t.copy();broken[sel,:,2]+=.035;rejected(lambda:wheels(broken,fleet,role))
 broken=t.copy();broken[eq,:,2]+=.08;rejected(lambda:equipment(broken,fleet,role))
 broken=t.copy();broken[eq,:,0]+=.15;rejected(lambda:equipment(broken,fleet,role))
 rows.append({'id':r['id'],'glass_visibility_backing':True,'actual_glass_faces_buried_and_floated_80mm_rejected':True,'wheel_or_suspended_contract':True,'roof_contact_80mm_lift_and_150mm_position_jump_rejected':True})
byid={r['id']:r for r in m['models']}
# Sample the actual near skin's shoulder perimeter. Sealed individual patch
# solids alone cannot detect daylight gaps between front and side shells.
for role in [CONTRACTS[fleet][0][0],CONTRACTS[fleet][0][-1]]:
 near,_=read(root/'models'/f'klrt-{fleet}-{role}.m3dmodel')
 far,_=read(root/'models'/f'klrt-{fleet}-{role}-far.m3dmodel')
 for height in ([.80,1.0,1.18,1.4,2.0,2.6] if fleet=='caf' else [.90,1.14,1.4,2.0,2.70]):
  skin=near[(near[:,:,1]>1.32).all(axis=1)]
  crossings=[]
  for j in range(3):
   a,b=skin[:,j],skin[:,(j+1)%3]
   mask=((a[:,2]<=height)&(b[:,2]>=height))|((b[:,2]<=height)&(a[:,2]>=height))
   mask &= abs(a[:,2]-b[:,2])>1e-7
   ratio=(height-a[mask,2])/(b[mask,2]-a[mask,2])
   crossings.extend((a[mask]+(b[mask]-a[mask])*ratio[:,None])[:,0])
  assert crossings,'no actual shoulder section'
  origin=np.array([max(crossings)-.03,1.60,height])
  for geometry in [near,far]:
   ds=ray(geometry,origin,np.array([0.,-1.,0.]));assert len(ds) and min(ds)<.285,'daylight gap at front/side shoulder'
for role in CONTRACTS[fleet][0]:
 a=byid[f'klrt-{fleet}-{role}'];b=byid[a['id']+'-far'];assert a['triangles']<=15000 and b['triangles']*2<a['triangles'],('LOD budget',role,a['triangles'],b['triangles'])
 for key in ['minimum','maximum']:assert np.max(abs(np.array(a[key])-b[key]))<.025,'LOD envelope jumped'
report={'status':'VERIFIED','fleet':fleet,'models':rows,'limits':'Exterior glass triangle samples and inner 24/25mm backing; 4 actual wheel envelopes per bogie module, roof central contact, 4 joint cross sections. No exhaustive self-intersection, engineering fidelity, dynamic articulation or Metal/device acceptance.'}
(root/'klrt-verification.json').write_text(json.dumps(report,indent=2)+'\n');print('VERIFIED',fleet,len(rows),'units/assemblies and actual fault mutations')
