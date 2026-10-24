"""Prove only the low forward cab shell changed from the actual prior delivery."""
from pathlib import Path
from collections import Counter
import sys,struct,json
root=Path(sys.argv[1]);prior=Path(sys.argv[2]);records=[]
def triangles(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def xs(t):return [struct.unpack_from('<f',t,4+j*16)[0] for j in range(3)]
for id in ['refresh-e200','refresh-700t-middle','refresh-700t-panto','metro-four-leading']:
 for suffix in ['.m3dmodel','.glb']:
  assert (root/'models'/(id+suffix)).read_bytes()==(prior/'models'/(id+suffix)).read_bytes(),id+suffix
 records.append({'id':id,'native_and_glb_bytes_unchanged':True})
for id,sign in [('refresh-700t-cab',1),('refresh-700t-tail',-1)]:
 old=triangles(prior/'models'/(id+'.m3dmodel'));new=triangles(root/'models'/(id+'.m3dmodel'))
 removed=list((Counter(old)-Counter(new)).elements());added=list((Counter(new)-Counter(old)).elements())
 assert removed and added
 for t in removed+added:assert min(x*sign for x in xs(t))>=9.4999,(id,'geometry behind nose changed')
 common=0
 for a,b in zip(reversed(old),reversed(new)):
  if a!=b:break
  common+=1
 assert common>5000,(id,'cab hardware/window/door/running-gear suffix not preserved')
 records.append({'id':id,'removed_triangles':len(removed),'added_triangles':len(added),'all_changed_triangles_forward_of_x_m':9.5*sign,'identical_trailing_triangles':common})
(root/'nose-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_producer':'7096130efa097d0e4c5b3b0dc6a12c004c080b38','checks':records},indent=2)+'\n')
print(json.dumps(records))
