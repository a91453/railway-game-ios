"""Actual native triangle payload comparison against the rejected, committed v1.
Optional third argument is the genuine intermediate before the owner's skirt edit.
"""
import collections,json,struct,sys
from pathlib import Path
root,previous=map(Path,sys.argv[1:3])
def read(path):
 b=path.read_bytes();count,size=struct.unpack_from('<II',b,8);offset=16+(size+3)//4*4
 return [b[offset+i*52:offset+(i+1)*52] for i in range(count)]
def vertices(t):return [struct.unpack_from('<fffI',t,4+j*16) for j in range(3)]
def bogie(t):
 v=vertices(t)
 return max(p[2] for p in v)<1.15 and min(abs(p[0]) for p in v)>2.5 and max(abs(p[0]) for p in v)<6.9 and max(abs(p[1]) for p in v)<1.3
rows=[]
for name in ['e1000','e1000-far']:
 old=read(previous/'models'/f'{name}.m3dmodel');new=read(root/'models'/f'{name}.m3dmodel');r={'id':name}
 # The roof body is white; equipment uses the existing steel/ink palette.
 # Derive the actual roof-body colour from the original large roof cap.
 white=next(vertices(t)[0][3] for t in old if all(3.9039<p[2]<3.9041 for p in vertices(t)))
 roof_filter=lambda t:min(p[2] for p in vertices(t))>=3.9039 and vertices(t)[0][3]!=white
 for label,predicate in [('roof_equipment',roof_filter),('bogie_running_gear',bogie)]:
  a=collections.Counter(t for t in old if predicate(t));b=collections.Counter(t for t in new if predicate(t))
  assert not a-b,(name,label,'protected triangles removed or changed')
  added=list((b-a).elements())
  if label=='roof_equipment':
   assert all(all(abs(p[2]-3.904)<.00001 for p in vertices(t)) for t in added),'unexpected added roof hardware'
   r['new_crown_support_top_triangles']=len(added)
  else:assert not added,(name,label,'unexpected new running gear')
  r[label+'_identical_triangles']=sum(a.values())
 if len(sys.argv)>3:
  interim=read(Path(sys.argv[3])/'models'/f'{name}.m3dmodel')
  a,b=collections.Counter(interim),collections.Counter(new);delta=list((a-b).elements())+list((b-a).elements())
  assert delta and all(min(p[0] for p in vertices(t))>7.2 and max(p[2] for p in vertices(t))<=1.151 for t in delta),'skirt follow-up changed geometry outside front lower skirt'
  r['owner_skirt_followup_changed_triangles']=len(delta)
  r['owner_skirt_followup_bounds']='all differing triangles x>7.2m and z<=1.151m; remaining complete triangle bytes identical'
 rows.append(r)
(root/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':'2be9dacaf2e1fa92b9fae6e3593cfa122aeeb189','models':rows,'limits':'Native selected hardware triangles unchanged, not a claim that the cab/body shell was unchanged. Roof crown and frontal underframe intentionally corrected.'},indent=2)+'\n')
print('VERIFIED true-v1 hardware and localized skirt follow-up')
