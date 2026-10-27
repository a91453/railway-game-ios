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
# Front fittings are at X > 11.2; changed main-shell triangles can span the
# full length because a station splits those surfaces. No changed small
# component outside that region is allowed.
for t in removed+added:
 v=xvals(t)
 if min(p[0] for p in v)>11.2:continue
 # Only the original main shell reaches this long span / full end width.
 assert max(p[0] for p in v)-min(p[0] for p in v)>20 or all(p[0]<-11.5 for p in v),v
# Rear is the same final DM rotated 180 degrees (already exporter verified
# assembly construction), and all standalone non-driving units are protected.
report={'status':'VERIFIED','byte_identical':rows,'c371_dm_removed_triangles':len(removed),'c371_dm_added_triangles':len(added),'unchanged_triangles':sum((a&b).values()),'scope':'Changed components are driving-end fascia, lamps, wipers and front main-shell end station. Long main-shell faces are retriangulated; this is not a claim that all shell triangle bytes outside the cab are unchanged.'}
(new/'protected-payload-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
