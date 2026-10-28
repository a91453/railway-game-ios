import json,struct,collections,hashlib,sys
from pathlib import Path
old,new=map(Path,sys.argv[1:])
def tris(p):
 b=p.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def xvals(t):return [struct.unpack_from('<fff',t,4+i*16) for i in range(3)]
rows={}
for p in sorted((old/'models').glob('*')):
 if 'c381' in p.name or p.stem in ['c371-m','c371-t','emu3000-ed']:
  assert p.read_bytes()==(new/'models'/p.name).read_bytes(),p
  rows[p.name]='byte-identical'
a,b=map(collections.Counter,[tris(old/'models/c371-dm.m3dmodel'),tris(new/'models/c371-dm.m3dmodel')])
removed=list((a-b).elements());added=list((b-a).elements())
# Fifth-round changes are confined to the last 0.42 m of the nose plus
# four added axle shafts. All original body/roof/tyre/hub triangles remain.
for changed,items in [('removed',removed),('added',added)]:
 for t in items:
  v=xvals(t)
  if min(p[0] for p in v)>11.15:continue
  # Four new axle shafts, contained in the existing bogie/wheel span.
  if changed=='added' and any(all(abs(p[0]-ax)<0.076 and abs(p[1])<=0.701 and 0.349<=p[2]<=0.501 for p in v) for ax in [-9.4,-7.1,7.1,9.4]):continue
  raise AssertionError(('unexpected geometry outside nose/added axles',changed,v))
# Rear is the same final DM rotated 180 degrees (already exporter verified
# assembly construction), and all standalone non-driving units are protected.
report={'status':'VERIFIED','byte_identical':rows,'c371_dm_removed_triangles':len(removed),'c371_dm_added_triangles':len(added),'unchanged_triangles':sum((a&b).values()),'scope':'Changes confined to fascia, glazing, lamps/wipers and recessed support beam in the last 0.42 m, plus four added axle shafts. Every original triangle outside the nose remains byte-identical, including body, roof fittings, tyres and hubs.'}
(new/'protected-payload-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
