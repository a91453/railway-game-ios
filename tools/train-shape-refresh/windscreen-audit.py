"""Measure the delivered windshield and prove every change stays in that mask."""
from pathlib import Path
from collections import Counter
import sys,struct,json
root,prior=map(Path,sys.argv[1:3]);records=[]
manifest=json.loads((root/'manifest.json').read_text());glass=manifest['livery']['high_speed']['glass_argb']
rim=(glass&0xff000000)|sum(int(((glass>>s)&255)*0.72+0.5)<<s for s in [0,8,16]);allowed={glass,rim}
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def vertices(ts):return [struct.unpack_from('<fffI',t,4+j*16) for t in ts for j in range(3)]
def inspect(folder):
 ts=read(folder/'models/refresh-700t-cab.m3dmodel');v=[p for p in vertices(ts) if p[0]>7 and p[3]==glass]
 high=max(p[2] for p in v);low=min(p[2] for p in v);width=max(p[1] for p in v)-min(p[1] for p in v)
 return {'mask_top_z_m':high,'mask_bottom_z_m':low,'mask_height_m':high-low,'mask_width_m':width,'width_height_ratio':width/(high-low),'white_roof_margin_m':3.65-high,'rear_x_m':min(p[0] for p in v),'checks':[3.65-high>0.23,high-low<1.0,width/(high-low)>2.2,min(p[0] for p in v)>8]}
for id in ['refresh-e200','refresh-700t-middle','refresh-700t-panto','metro-four-leading']:
 for suffix in ['.m3dmodel','.glb']:assert (root/'models'/(id+suffix)).read_bytes()==(prior/'models'/(id+suffix)).read_bytes(),id+suffix
 records.append({'id':id,'native_and_glb_byte_identical':True})
for id,sign in [('refresh-700t-cab',1),('refresh-700t-tail',-1)]:
 old,new=read(prior/'models'/(id+'.m3dmodel')),read(root/'models'/(id+'.m3dmodel'))
 removed=list((Counter(old)-Counter(new)).elements());added=list((Counter(new)-Counter(old)).elements());assert removed and added
 for p in vertices(removed+added):assert p[0]*sign>7 and p[3] in allowed,(id,'change outside windscreen/rim',p)
 records.append({'id':id,'removed_mask_or_rim_triangles':len(removed),'added_mask_or_rim_triangles':len(added),'unchanged_triangles_byte_identical':sum((Counter(old)&Counter(new)).values()),'only_windscreen_and_rim_changed':True})
old,new=inspect(prior),inspect(root);assert not all(old['checks']),old;assert all(new['checks']),new
assert manifest['assemblies']==json.loads((prior/'manifest.json').read_text())['assemblies']
(root/'windscreen-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_actual_delivery':old,'final_actual_delivery':new,'unchanged_scope':records,'limits':'display-geometry criteria, not engineering dimensions or photographic similarity; reference images inspected separately'},indent=2)+'\n')
print('VERIFIED lowered windscreen and white roof margin, prior rejected',old,new,records)
