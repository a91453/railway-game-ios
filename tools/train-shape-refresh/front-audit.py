"""Inspect real native front geometry and the untouched delivered units."""
from pathlib import Path
from collections import Counter
import sys,struct,json,runpy
import numpy as np
root,prior=map(Path,sys.argv[1:3]);manifest=json.loads((root/'manifest.json').read_text())
glass=manifest['livery']['high_speed']['glass_argb'];body=manifest['livery']['high_speed']['body_argb']
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def vertices(ts):return [struct.unpack_from('<fffI',t,4+j*16) for t in ts for j in range(3)]
def inspect(folder):
 ts=read(folder/'models/refresh-700t-cab.m3dmodel');vs=vertices(ts)
 mask=[p for p in vs if p[0]>7 and p[3]==glass]
 high=max(p[2] for p in mask);low=min(p[2] for p in mask);width=max(p[1] for p in mask)-min(p[1] for p in mask)
 floor=min(p[2] for p in vs if p[0]>7)
 section=[p for p in vs if abs(p[0]-11.9)<0.0001 and p[3]==body]
 inset_width=max(p[1] for p in section)-min(p[1] for p in section)
 # Front projection: actual white boundary vertices near the centreline.
 white=[p for p in vs if p[0]>11 and p[3]==body and abs(p[1])<0.20]
 return {'mask_top_z_m':high,'mask_bottom_z_m':low,'mask_height_m':high-low,'mask_width_m':width,'width_height_ratio':width/(high-low),'white_roof_margin_m':3.65-high,'front_shell_low_z_m':floor,'white_inset_width_at_x11_9_m':inset_width,'white_nose_centre_low_z_m':min(p[2] for p in white),'checks':[3.65-high>0.23,high-low<1.0,width<2.25,floor<0.45]}
records=[]
for id in ['refresh-e200','refresh-700t-middle','refresh-700t-panto','metro-four-leading']:
 for suffix in ['.m3dmodel','.glb']:assert (root/'models'/(id+suffix)).read_bytes()==(prior/'models'/(id+suffix)).read_bytes(),id+suffix
 records.append({'id':id,'native_and_glb_byte_identical':True})
for id,sign in [('refresh-700t-cab',1),('refresh-700t-tail',-1)]:
 old,new=read(prior/'models'/(id+'.m3dmodel')),read(root/'models'/(id+'.m3dmodel'))
 removed=list((Counter(old)-Counter(new)).elements());added=list((Counter(new)-Counter(old)).elements());assert removed and added
 for p in vertices(removed+added):assert p[0]*sign>=3.6999,(id,'change outside nose',p)
 records.append({'id':id,'removed_front_triangles':len(removed),'added_front_triangles':len(added),'unchanged_triangles_byte_identical':sum((Counter(old)&Counter(new)).values()),'all_changes_in_front_x_ge_3_7_m':True})
old,new=inspect(prior),inspect(root);assert not all(old['checks']),old;assert all(new['checks']),new
assert new['white_inset_width_at_x11_9_m']>old['white_inset_width_at_x11_9_m']*1.5,'White inset still ends in the preceding narrow V'
assert manifest['assemblies']==json.loads((prior/'manifest.json').read_text())['assemblies']
# Independent rays prove the new shell obscures the upper front wheels in a
# frontal view. This checks real visible coverage, not just the lowest vertex.
a=runpy.run_path(str(Path(__file__).with_name('support-audit.py')))
def coverage(folder):
 p,c=a['read'](folder/'models/refresh-700t-cab.m3dmodel')
 tires=np.all(c==(43|(46<<8)|(52<<16)),axis=1)
 wheelpoints=np.unique(np.round(p[tires].reshape(-1,3),5),axis=0)
 points=wheelpoints[(wheelpoints[:,0]>0)&(wheelpoints[:,2]>=0.55)]
 shell=p[np.all(p[:,:,0]>=5.8,axis=1)]
 hits=[a['nearest'](np.array([30.,q[1],q[2]]),np.array([-1.,0.,0.]),shell)<30-q[0] for q in points]
 return {'upper_wheel_vertex_samples':len(hits),'covered_by_front_shell':int(sum(hits)),'fully_covered':all(hits)}
old_cover,new_cover=coverage(prior),coverage(root);assert not old_cover['fully_covered'];assert new_cover['fully_covered'],new_cover
result={'status':'VERIFIED','prior_actual_delivery':old,'final_actual_delivery':new,'front_wheel_occlusion':{'prior':old_cover,'final':new_cover},'unchanged_scope':records,'limits':'model coordinates and frontal upper-wheel ray samples, not engineering dimensions, photo similarity or all-surface collisions; appearance inspected separately'}
(root/'front-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
