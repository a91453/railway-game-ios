"""Ray checks against actual native triangles, not recipe constants."""
import json,struct,sys
from pathlib import Path
import numpy as np
root=Path(sys.argv[1])
def read(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);k=16+(size+3)//4*4
 t=np.array([[struct.unpack_from('<fff',b,k+i*52+4+j*16) for j in range(3)] for i in range(n)])
 col=np.array([struct.unpack_from('<I',b,k+i*52+16)[0]&0xffffff for i in range(n)])
 return t,col

def hits(point,direction,tri):
 e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(np.broadcast_to(direction,e2.shape),e2);a=np.einsum('ij,ij->i',e1,h)
 use=abs(a)>1e-9;e1=e1[use];e2=e2[use];h=h[use];a=a[use];s=point-tri[use,0];u=np.einsum('ij,ij->i',s,h)/a;q=np.cross(s,e1);v=q@direction/a;dist=np.einsum('ij,ij->i',e2,q)/a
 return dist[(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(dist>=-1e-5)]
def glasses(t,col,shift=0):
 panes=t[col==0x403c26];solids=t[col!=0x403c26];tested=0
 for tri in panes:
  p=tri.mean(axis=0)
  # Only outward broad glass faces, not thin rims/back faces.
  n=np.cross(tri[1]-tri[0],tri[2]-tri[0]);n=n/np.linalg.norm(n)
  if abs(p[1])>1.4 and n[1]*p[1]>0.5:
   d=np.array([0,-np.sign(p[1]),0]);p=p+np.array([0,np.sign(p[1])*shift,0])
  elif p[0]>9.7 and n[0]>0.8:
   d=np.array([-1,0,0]);p=p+np.array([shift,0,0])
  else:continue
  h=hits(p,d,solids);assert len(h) and h.min()<0.065,'unsupported glazing';tested+=1
 assert tested>10
 return tested
def visible_front_glass(t,col):
 panes=t[col==0x403c26]
 # Body/door blue and silver, excluding intentional dark wipers and lamp housings.
 body=t[np.isin(col,[0x914f1d,0xd2d0c8])]
 tested=0
 for tri in panes:
  p=tri.mean(axis=0);n=np.cross(tri[1]-tri[0],tri[2]-tri[0]);n=n/np.linalg.norm(n)
  if p[0]>9.7 and n[0]>0.8:
   distances=hits(p+np.array([0.0001,0,0]),np.array([1,0,0]),body)
   assert not np.any((distances>0)&(distances<0.12)), 'glass buried by actual cap/door triangles'
   tested+=1
 return tested
rows=[]
for m in json.loads((root/'manifest.json').read_text())['models']:
 if m['category']!='section':continue
 t,col=read(root/m['native']);n=glasses(t,col)
 visible=visible_front_glass(t,col)
 if m['id'] in ['emu500-emc','emu500-em']:
  assert visible>4
  buried=t.copy();mask=(col==0x403c26)&(t.mean(axis=1)[:,0]>9.7);buried[mask,:,0]-=0.14
  try:visible_front_glass(buried,col)
  except AssertionError:pass
  else:raise AssertionError('buried front glass fault not rejected')
 try:glasses(t,col,shift=0.25)
 except AssertionError:pass
 else:raise AssertionError('floating glass fault not rejected')
 # HVAC contact at centre of actual housing base: supporting roof intersects immediately.
 for x in [-7.8,7.8]:
  p=np.array([x,0,3.6501]);h=hits(p,np.array([0,0,-1]),t);assert len(h) and h.min()<0.02
 rows.append({'id':m['id'],'broad_glass_faces_backed':n,'HVAC_roof_contact_samples':2,'front_glass_faces_visible':visible})
(root/'support-verification.json').write_text(json.dumps({'status':'VERIFIED','checks':['broad outward glass faces raycast to non-glass backing within 65 mm','250 mm floating glass fault rejected','HVAC centre roof contact','front glass not buried by actual body/door triangles','140 mm buried glass fault rejected'],'limits':['ray samples do not exhaust all components or intersections','roof side edges intentionally overhang centre supports'],'models':rows},indent=2)+'\n')
print('VERIFIED sampled glazing backing, floating-glass rejection and roof contact')
