"""Exact native payload audit for charcoal exterior -> game slate; functional hardware stays charcoal. No geometry subdivision allowed."""
from pathlib import Path
import sys,json,struct,hashlib,copy,collections
import numpy as np
out,prior=map(Path,sys.argv[1:]);new=json.loads((out/'manifest.json').read_text());old=json.loads((prior/'manifest.json').read_text())
def rows(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 assert len(b)==start+n*52
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def rgb(h):return 0xff000000|((h&255)<<16)|(h&0xff00)|((h>>16)&255)
def shade(c,factor):return 0xff000000|sum(int(np.floor(np.float32((c>>(8*i))&255)*np.float32(factor)+.5))<<(8*i) for i in range(3))
a,b=old['palette']['mask'],new['palette']['mask'];allowed={a:b}
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
   assert d==c or (c==a and d==b),'non-charcoal material changed'
   if c!=d: assert min(v[2] for v in p)>1.25,'functional underframe recoloured'
   changes+=c!=d
  def normal(t):
   t=np.array(t);n=np.cross(t[1]-t[0],t[2]-t[0]);return (n/np.linalg.norm(n)).astype('<f4').tobytes()
  assert normal(p)==normal(q),'actual face normal changed'
  if min(v[2] for v in p)>=3.75 or max(v[2] for v in p)<=1.25: assert x==y,'functional hardware changed'
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
  at=next((4+j*16+12 for j in range(3) if struct.unpack_from('<I',t,4+j*16+12)[0] not in allowed and struct.unpack_from('<I',t,4+j*16+12)[0]!=b),None)
  if at is not None:
   v=bytearray(bad[i]);struct.pack_into('<I',v,at,b);bad[i]=bytes(v);break
 try:audit(before,bad)
 except AssertionError:pass
 else:raise AssertionError('non-charcoal repaint accepted')
 # Actual old-charcoal front wiper solids, distinguished from side trim by bounds.
 def groups():
  ids=[i for i,t in enumerate(before) if all(struct.unpack_from('<I',t,16+j*16)[0]==a for j in range(3))]
  parent={i:i for i in ids};vertices={}
  def find(i):
   while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
   return i
  for i in ids:
   for j in range(3):
    k=before[i][4+j*16:16+j*16];other=vertices.setdefault(k,i);parent[find(i)]=find(other)
  groups=collections.defaultdict(list)
  for i in ids:groups[find(i)].append(i)
  return groups.values()
 wiper_records=0
 for group in groups():
  pts=np.array([struct.unpack_from('<fff',before[i],4+j*16) for i in group for j in range(3)]);lo=pts.min(0);hi=pts.max(0)
  if min(abs(lo[0]),abs(hi[0]))>7.5 and max(abs(lo[1]),abs(hi[1]))<.8 and hi[1]-lo[1]<.15 and lo[2]>2.25 and hi[2]<3.15 and hi[2]-lo[2]<.65:
   assert all(before[i]==after[i] for i in group),'actual wiper recoloured or moved'
   wiper_records+=len(group)
 if m['id'] in ['emu3000-ed','emu3000-tail']: assert wiper_records>0,'no near wiper audit samples'
 records.append({'id':n,'triangles':len(after),'preserved_actual_wiper_triangles':wiper_records,'recoloured_vertices':changed,'geometry_flags_topology_normals':'byte-identical / normals recomputed','mutations_rejected':['5mm actual corner shift','recolour non-charcoal vertex']})
result={'status':'VERIFIED','producer_commit':new['producer_commit'],'previous_producer_commit':old['producer_commit'],'palette_pairs':{hex(k):hex(v) for k,v in allowed.items()},'models':records,'functional_hardware':'wheel / underframe <=1.25m and roof mechanisms >=3.75m records preserved','assembly_unchanged':new['assembly']==old['assembly'],'no_surface_subdivision':True,'palette_request':'slate #6E7487; glass, white, teal, steel, lamps and functional charcoal preserved','limits':'Exact virtual-model payload comparison, not engineering accuracy or animation proof.'}
assert new['assembly']==old['assembly'],'assembly placements changed'
(out/'paint-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('VERIFIED paint-only change for',len(records),'near/far units')
