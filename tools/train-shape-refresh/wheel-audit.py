"""Actual tire-component contact and upper clearance rays; no recipe positions."""
import runpy,sys,json
from pathlib import Path
import numpy as np
# Reuse the independent byte reader and ray solver, including support assertions.
a=runpy.run_path(str(Path(__file__).with_name('support-audit.py')));root=a['root'];records=[]
for m in a['manifest']['models']:
 if m['category']!='section':continue
 p,c=a['read'](root/m['native']);mask=np.all(c==(43|(46<<8)|(52<<16)),axis=1);t=p[mask]
 assert len(t),m['id']
 # Connected components by shared exported positions.
 groups=[];todo=set(range(len(t)));index={}
 for i,tri in enumerate(t):
  for v in tri:index.setdefault(tuple(np.round(v,5)),set()).add(i)
 while todo:
  stack=[todo.pop()];ids=set(stack)
  while stack:
   for v in t[stack.pop()]:
    for k in index[tuple(np.round(v,5))]&todo:todo.remove(k);ids.add(k);stack.append(k)
  groups.append(t[list(ids)].reshape(-1,3))
 clear=[]
 for points in groups:
  lo=points.min(axis=0);hi=points.max(axis=0);assert abs(lo[2])<1e-5,(m['id'],'tire floats',lo.tolist())
  side=hi[1] if hi[1]>0 else lo[1];origin=np.array([(lo[0]+hi[0])/2,side,hi[2]])
  d=a['nearest'](origin,np.array([0.,0.,1.]),p[~mask]);clear.append(d)
  assert d>=0.005,(m['id'],'wheel/body clearance',d)
 records.append({'id':m['id'],'actual_tire_components':len(groups),'all_tire_bottoms_on_rail':True,'minimum_upward_clearance_m':min(clear)})
(root/'wheel-verification.json').write_text(json.dumps({'status':'VERIFIED','models':records,'limits':'upper outer tire surface rays only; not suspension dynamics or full collision detection'},indent=2)+'\n')
print(json.dumps(records))
