"""Audit actual revision payloads; never substitute bounds for protected triangles."""
import json,struct,sys,collections
from pathlib import Path
import numpy as np
prior,current=map(Path,sys.argv[1:3]);old=json.loads((prior/'manifest.json').read_text());new=json.loads((current/'manifest.json').read_text());rows=[]
def read(p):
 b=p.read_bytes();n,m=struct.unpack_from('<II',b,8);s=16+(m+3)//4*4
 records=[b[s+i*52:s+(i+1)*52] for i in range(n)]
 points=np.array([[struct.unpack_from('<fff',r,4+j*16) for j in range(3)] for r in records]);colors=np.array([struct.unpack_from('<I',r,16)[0] for r in records],dtype=np.uint32)
 return points,colors,records
def components(p):
 parent=list(range(len(p)));seen={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i,t in enumerate(p):
  for v in t:
   key=tuple(np.round(v,5));j=seen.setdefault(key,i);parent[find(i)]=find(j)
 groups=collections.defaultdict(list)
 for i in range(len(p)):groups[find(i)].append(i)
 return list(groups.values())
def turns(p,c,navy):
 edges=collections.Counter();positions={}
 for tri in p[c==navy]:
  keys=[tuple(np.round(v,5)) for v in tri]
  for a,b in zip(keys,keys[1:]+keys[:1]):edges[tuple(sorted((a,b)))]+=1;positions[a]=np.array(a)[1:]
 neighbours=collections.defaultdict(list)
 for (a,b),count in edges.items():
  if count==1:neighbours[a].append(b);neighbours[b].append(a)
 angles=[]
 for key,adj in neighbours.items():
  if len(adj)!=2:continue
  a,b=[positions[x]-positions[key] for x in adj];length=np.linalg.norm(a)*np.linalg.norm(b)
  if length>1e-12:angles.append(180-float(np.degrees(np.arccos(np.clip(a.dot(b)/length,-1,1)))))
 return {'boundary_vertices':len(neighbours),'turns_over_70_degrees':sum(x>70 for x in angles),'maximum_turn_degrees':max(angles,default=0)}
for m in new['models']:
 if m['category']!='section' or m['id'].endswith('-light'):continue
 source=next(x for x in old['models'] if x['id']==m['id']);p,c,recs=read(prior/source['native']);q,d,nextrecs=read(current/m['native']);available=collections.Counter(nextrecs)
 ids=np.flatnonzero(c==old['palette']['hardware']);groups=components(p[ids]);tires=[]
 for g in groups:
  chosen=ids[g];lo=p[chosen].min(axis=(0,1));hi=p[chosen].max(axis=(0,1))
  if abs(lo[2])<1e-5 and abs(hi[2]-.86)<1e-5:tires.append(chosen)
 assert len(tires)==8,m['id']
 protected=collections.Counter(recs[i] for g in tires for i in g)
 assert not (protected-available),(m['id'],'actual tread position/colour/flags/topology changed')
 # Roof equipment stays at its actual old positions and old material colours.
 roof=np.flatnonzero(p[:,:,2].min(1)>=3.65-1e-5)
 # Exclude body-shell top faces: their colour deliberately changes, unlike AC/collector.
 roof=[i for i in roof if not (c[i]==old['palette']['body'] and abs(p[i,:,2].min()-3.65)<1e-5)]
 for i in roof:assert available[recs[i]]>0,(m['id'],'protected equipment triangle changed',i)
 def geometry(record):return record[:4]+b''.join(record[4+j*16:16+j*16] for j in range(3))
 new_geometry=collections.Counter(geometry(r) for r in nextrecs)
 sign=-1 if '-reverse' in m['id'] else 1
 stable=[i for i in range(len(p)) if not m['id'].startswith('emu900-ed') or (p[i,:,0]*sign).max()<=8.35001 and (p[i,:,0]*sign).min()<8.34999]
 protected_geometry=collections.Counter(geometry(recs[i]) for i in stable)
 assert not (protected_geometry-new_geometry),(m['id'],'geometry outside permitted cab revision changed')
 for i in stable:
  if c[i] not in [old['palette']['body'],old['palette']['glass']]:assert available[recs[i]]>0,(m['id'],'protected functional material changed',i)
 row={'stable_original_geometry_triangles':len(stable),'id':m['id'],'eight_actual_tires_preserved':True,'exact_tread_triangle_records':sum(len(g) for g in tires),'exact_roof_equipment_triangle_records':len(roof)}
 if m['id'].startswith('emu900-ed'):row['navy_boundary_before']=turns(p,c,old['palette']['navy']);row['navy_boundary_after']=turns(q,d,new['palette']['navy'])
 rows.append(row)
(current/'revision-geometry-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_producer':old['producer_commit'],'current_producer':new['producer_commit'],'checks':['actual eight connected tires: each complete 52-byte triangle record retained (positions, colour, glow flags, topology; face normals derived from unchanged triangles)','actual AC and collector triangles retained, excluding intentionally recoloured body-shell top','navy perimeter projected turning angles measured from actual boundary edges; an observation, not a photo-similarity score'],'models':rows},indent=2))
print('VERIFIED protected actual tyre and roof equipment triangle records',len(rows))
print([r for r in rows if r['id']=='emu900-ed'])
