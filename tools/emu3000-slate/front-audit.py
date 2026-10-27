"""Actual native front projection, ray visibility and round lenses; no recipe UV tables."""
from pathlib import Path
import sys,json,struct,collections
import numpy as np
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());glass=manifest['palette']['glass']
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 a=np.array([[struct.unpack_from('<fffI',b,start+i*52+4+j*16) for j in range(3)] for i in range(n)])
 return a[:,:,:3],a[:,0,3].astype(np.uint32),np.array([struct.unpack_from('<I',b,start+i*52)[0] for i in range(n)])
def hits(o,d,p):
 a=p[:,0];e=p[:,1]-a;f=p[:,2]-a;h=np.cross(d,f);det=np.einsum('ij,ij->i',e,h);inv=np.divide(1,det,out=np.zeros(len(det)),where=abs(det)>1e-12);s=o-a;u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e);v=inv*np.einsum('j,ij->i',d,q);t=inv*np.einsum('ij,ij->i',f,q)
 return np.where((abs(det)>1e-12)&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>=0),t,np.inf)
def groups(p):
 parent=list(range(len(p)));vertices={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i,t in enumerate(p):
  for v in t:
   k=tuple(np.round(v,5));j=vertices.setdefault(k,i);parent[find(i)]=find(j)
 out=collections.defaultdict(list)
 for i in range(len(p)):out[find(i)].append(i)
 return list(out.values())
rows=[]
for rec in manifest['models']:
 if rec['id'] not in ['emu3000-ed','emu3000-tail','emu3000-ed-far','emu3000-tail-far']:continue
 p,c,layer=read(root/rec['native']);sign=-1 if 'tail' in rec['id'] else 1;p[:,:,:2]*=sign
 n=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);areas=np.linalg.norm(n,axis=1);n/=areas[:,None];centres=p.mean(axis=1)
 # Front/up-facing main pane faces with area >0.01m2; exclude thin perimeter walls.
 idx=np.where((c==glass)&(n[:,0]>.25)&(n[:,2]>.25)&(centres[:,0]>7.5)&(abs(centres[:,1])<1.02)&(centres[:,2]>2.36)&(centres[:,2]<3.23)&(areas>.02))[0]
 hidden=[];wiper_samples=0;wipers=set()
 for part in groups(p[c==manifest['palette']['hardware']]):
  ids=np.where(c==manifest['palette']['hardware'])[0][part];q=p[ids].reshape(-1,3);lo=q.min(0);hi=q.max(0)
  if hi[1]-lo[1]<.15 and lo[2]>2.25 and hi[2]<3.15 and hi[2]-lo[2]<.65:wipers.update(map(int,ids))
 for i in idx:
  o=centres[i]+[.4,0,0];depths=hits(o,np.array([-1.,0,0]),p);hit=int(depths.argmin());depth=depths[hit]
  if depth<.397:
   if hit in wipers:wiper_samples+=1
   else:hidden.append((int(i),float(.4-depth)))
 assert len(idx)>=8,(rec['id'],'no real windscreen samples')
 assert not hidden,(rec['id'],'covered windshield',hidden)
 # Connected glow solids: front-plane bounding boxes directly expose stretched lamps.
 lamp_rows=[]
 for part in groups(p[layer==1]):
  q=p[layer==1][part].reshape(-1,3);lo=q.min(0);hi=q.max(0)
  if abs(q[:,1].mean())>.35:
   aspect=float((hi[2]-lo[2])/(hi[1]-lo[1]));assert .75<aspect<1.35,(rec['id'],'stretched lamp',aspect)
   lamp_rows.append({'width_m':float(hi[1]-lo[1]),'height_m':float(hi[2]-lo[2]),'front_aspect':aspect})
 assert len(lamp_rows)==2
 # Sink the actual connected windshield solid 120mm into the real shell.
 glass_ids=np.where(c==glass)[0];pane=next(part for part in groups(p[c==glass]) if idx[0] in glass_ids[part])
 moved=p.copy();moved[glass_ids[pane],:,0]-=.12
 mutation_hidden=0
 for i in idx:
  o=moved[i].mean(axis=0)+[.4,0,0]
  if hits(o,np.array([-1.,0,0]),moved).min()<.37:mutation_hidden+=1
 assert mutation_hidden>0,(rec['id'],'buried windshield mutation escaped')
 rows.append({'id':rec['id'],'windscreen_samples':len(idx),'intended_thin_wiper_occlusions':wiper_samples,'buried_windscreen_mutation_occluded_samples':mutation_hidden,'round_lower_lamps':lamp_rows})
(root/'front-verification.json').write_text(json.dumps({'status':'VERIFIED','method':'actual native front projection; frontal windshield centroid rays against every real triangle; connected glowing lens front bounds; round lower lamps checked for head and tail near/far','models':rows,'limits':'static centroid samples; source image is a proportion reference, not an engineering front section or similarity score'},indent=2)+'\n')
print('VERIFIED actual front windshield visibility and round head/tail lamps, near/far')
