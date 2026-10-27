"""Exact native payload audit for orange -> game navy. No geometry subdivision allowed."""
from pathlib import Path
import sys,json,struct,hashlib,copy
import numpy as np
out,prior=map(Path,sys.argv[1:]);new=json.loads((out/'manifest.json').read_text());old=json.loads((prior/'manifest.json').read_text())
def rows(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 assert len(b)==start+n*52
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def rgb(h):return 0xff000000|((h&255)<<16)|(h&0xff00)|((h>>16)&255)
def shade(c,factor):return 0xff000000|sum(int(np.floor(np.float32((c>>(8*i))&255)*np.float32(factor)+.5))<<(8*i) for i in range(3))
a,b=rgb(0xE2662A),rgb(0x262C57);allowed={a:b,**{shade(a,f):shade(b,f) for f in [.7,.8,.86,.92]}}
def audit(before,after):
 assert len(before)==len(after),'triangle topology count changed'
 changes=0
 for x,y in zip(before,after):
  assert x[:4]==y[:4],'layer/glow flags changed'
  p=[];q=[]
  for i in range(3):
   at=4+i*16
   assert x[at:at+12]==y[at:at+12],'actual vertex position/topology changed'
   p.append(struct.unpack_from('<fff',x,at));q.append(struct.unpack_from('<fff',y,at))
   c,d=struct.unpack_from('<I',x,at+12)[0],struct.unpack_from('<I',y,at+12)[0]
   assert d==allowed.get(c,c),'non-orange paint changed or wrong navy'
   changes+=c!=d
  def normal(t):
   t=np.array(t);n=np.cross(t[1]-t[0],t[2]-t[0]);return (n/np.linalg.norm(n)).astype('<f4').tobytes()
  assert normal(p)==normal(q),'actual face normal changed'
 assert changes>0,'no orange paint changed'
 return changes
records=[];oldmodels={m['id']:m for m in old['models']}
for m in new['models']:
 if m['category']!='section':continue
 n=m['id'];before=rows(prior/oldmodels[n]['native']);after=rows(out/m['native']);changed=audit(before,after)
 # A real corner movement and a non-orange colour corruption must fail.
 moved=list(after);v=bytearray(moved[0]);struct.pack_into('<f',v,4,struct.unpack_from('<f',v,4)[0]+.005);moved[0]=bytes(v)
 try:audit(before,moved)
 except AssertionError:pass
 else:raise AssertionError('moved vertex was accepted')
 bad=list(after)
 for i,t in enumerate(before):
  at=next((4+j*16+12 for j in range(3) if struct.unpack_from('<I',t,4+j*16+12)[0] not in allowed),None)
  if at is not None:
   v=bytearray(bad[i]);struct.pack_into('<I',v,at,b);bad[i]=bytes(v);break
 try:audit(before,bad)
 except AssertionError:pass
 else:raise AssertionError('non-orange repaint accepted')
 records.append({'id':n,'triangles':len(after),'recoloured_vertices':changed,'geometry_flags_topology_normals':'byte-identical / normals recomputed','mutations_rejected':['5mm actual corner shift','recolour non-orange vertex']})
for n in ['e500','e500-far','emu3000-ed','before-chukuang-standard']:
 m=next(m for m in new['models'] if m['id']==n);o=oldmodels[n]
 assert (out/m['native']).read_bytes()==(prior/o['native']).read_bytes(),n
 assert (out/m['glb']).read_bytes()==(prior/o['glb']).read_bytes(),n
result={'status':'VERIFIED','producer_commit':new['producer_commit'],'previous_producer_commit':old['producer_commit'],'palette_pairs':{hex(k):hex(v) for k,v in allowed.items()},'models':records,'protected_native_and_glb':['e500','e500-far','emu3000-ed','before-chukuang-standard'],'no_surface_subdivision':True,'limits':'Exact virtual-model payload comparison, not engineering accuracy or animation proof.'}
(out/'paint-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('VERIFIED paint-only change for',len(records),'near/far units')
