"""Check real exported palette/geometry against the true preceding native models."""
import collections,json,struct,sys,math
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);prior=Path(sys.argv[2]);m=json.loads((root/'manifest.json').read_text());before=json.loads((prior/'manifest.json').read_text())
def read(path):
 b=path.read_bytes();n,s=struct.unpack_from('<II',b,8);k=16+(s+3)//4*4
 p=np.array([[struct.unpack_from('<fff',b,k+i*52+4+j*16) for j in range(3)] for i in range(n)])
 c=[struct.unpack_from('<I',b,k+i*52+16)[0]&0xffffff for i in range(n)]
 return p,c

def count(t):return collections.Counter(tuple(v for point in tri for v in point) for tri in t)
def lum(native):
 channels=[(native>>shift)&255 for shift in [0,8,16]]
 linear=[v/255/12.92 if v/255<=0.04045 else ((v/255+0.055)/1.055)**2.4 for v in channels]
 return sum(a*b for a,b in zip(linear,[.2126,.7152,.0722]))
def contrast(a,b):
 a,b=lum(a),lum(b);return (max(a,b)+.05)/(min(a,b)+.05)
rows=[]
for model in m['models']:
 if model['category']!='section':continue
 old=next(a for a in before['models'] if a['id']==model['id'])
 a,ac=read(prior/old['native']);b,bc=read(root/model['native'])
 palette=m['native_palette']
 for role in ['body','accent','glass','frame','mask','roof']:assert palette[role] in bc,(model['id'],role)
 assert 0x914f1d not in bc and 0xd2d0c8 not in bc,'old real-world blue/silver left in final mesh'
 # Ignore colours while comparing actual triangle coordinates in protected regions.
 for name,mask in [('wheel_and_bogie',lambda t:(t[:,:,2].max(axis=1)<.96)&(np.abs(t[:,:,0]).max(axis=1)<9)),('roof',lambda t:t[:,:,2].min(axis=1)>=3.65)]:
  assert count(a[mask(a)])==count(b[mask(b)]),(model['id'],name)
 removed=count(a)-count(b);added=count(b)-count(a)
 for tri in list(removed)+list(added):
  for x,y,z in zip(tri[0::3],tri[1::3],tri[2::3]):
   assert (9.7<x<10.09 and abs(y)<1.4 and .16<z<3.4) or (abs(y)>1.4 and 1.10<z<3.3),'shape change outside frames, door layers, apron and coupler'
 for axis in [0,2]:
  assert abs(a[:,:,axis].min()-b[:,:,axis].min())<1e-5
  assert abs(a[:,:,axis].max()-b[:,:,axis].max())<1e-5
 rows.append({'id':model['id'],'removed_triangles':sum(removed.values()),'added_triangles':sum(added.values()),'protected_geometry':['wheel/bogie','roof','length and height envelope']})
assert m['assembly']==before['assembly']
ratios={f'{a}/{b}':round(contrast(m['native_palette'][a],m['native_palette'][b]),3) for a,b in [('body','accent'),('body','glass'),('body','frame')]}
assert ratios['body/accent']>3 and ratios['body/glass']>3 and ratios['body/frame']>3
(root/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_producer':(prior/'producer-commit.txt').read_text().strip(),'checks':['native actual palette adoption; no old blue/silver','protected actual triangle positions, not recipe constants','all changed geometry limited to frames/door layers/apron/coupler','assembly and length/height unchanged'],'unlit_palette_contrast':ratios,'limits':['contrast numbers refer to unlit sRGB swatches, not every rendered pixel','mirrored unseen equipment remains a proportional assumption'],'models':rows},indent=2)+'\n')
print('VERIFIED actual palette, protected geometry, local shape changes and unlit contrast',ratios)
