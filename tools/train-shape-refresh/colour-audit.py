"""Prove white-body livery scope: green faces unchanged, black fine stripe added."""
from pathlib import Path
from collections import Counter
import sys,struct,json
root,prior=map(Path,sys.argv[1:3]);records=[]
def decode(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def colours(t):return [struct.unpack_from('<I',t,16+j*16)[0] for j in range(3)]
for id in ['refresh-e200','metro-four-leading']:
 for suffix in ['.m3dmodel','.glb']:
  assert (root/'models'/(id+suffix)).read_bytes()==(prior/'models'/(id+suffix)).read_bytes(),id+suffix
 records.append({'id':id,'native_and_glb_byte_identical':True})
manifest=json.loads((root/'manifest.json').read_text());old_manifest=json.loads((prior/'manifest.json').read_text())
body=manifest['livery']['high_speed']['body_argb'];glass=manifest['livery']['high_speed']['glass_argb'];accent=manifest['livery']['high_speed']['accent_argb']
for id in ['refresh-700t-cab','refresh-700t-middle','refresh-700t-panto','refresh-700t-tail']:
 old,new=decode(prior/'models'/(id+'.m3dmodel')),decode(root/'models'/(id+'.m3dmodel'))
 green=lambda ts:Counter(t for t in ts if all(c&0xffffff==0x8c8c3e for c in colours(t)))
 assert green(old)==green(new),(id,'green shape/colour changed')
 glowing=lambda ts:Counter(t for t in ts if struct.unpack_from('<I',t)[0])
 assert glowing(old)==glowing(new),(id,'light geometry/flags/colour changed')
 added=list((Counter(new)-Counter(old)).elements());removed=list((Counter(old)-Counter(new)).elements())
 assert added and removed
 assert all(all(c==body for c in colours(t)) for t in removed),(id,'non-white surface altered')
 assert all(all(c in (body,accent) for c in colours(t)) for t in added),(id,'unexpected colour alteration')
 records.append({'id':id,'green_triangles_byte_identical':sum(green(new).values()),'glowing_triangles_byte_identical':sum(glowing(new).values()),'removed_white_triangles':len(removed),'added_white_or_black_triangles':len(added)})
assert manifest['assemblies']==old_manifest['assemblies']
for a,b in zip(manifest['models'],old_manifest['models']):assert (a['id'],a['minimum'],a['maximum'])==(b['id'],b['minimum'],b['maximum'])
rgb=lambda c:[(c>>n)&255 for n in [0,8,16]]
def luminance(c):
 return sum(w*(u/12.92 if u<=.04045 else ((u+.055)/1.055)**2.4) for w,u in zip((.2126,.7152,.0722),[v/255 for v in rgb(c)]))
def ratio(a,b):return (max(luminance(a),luminance(b))+.05)/(min(luminance(a),luminance(b))+.05)
contrast={'teal_white':ratio(0xff8c8c3e,body),'black_white':ratio(accent,body),'black_teal':ratio(accent,0xff8c8c3e),'glass_white':ratio(glass,body)}
assert all(v>=3 for v in contrast.values()),contrast
(root/'colour-verification.json').write_text(json.dumps({'status':'VERIFIED','scope':'warm white body retained; teal unchanged; black fine stripe only. Coplanar surface/area proof is separate paint-verification.json.','models':records,'unlit_srgb_contrast':contrast,'body_rgb':rgb(body),'glass_rgb':rgb(glass),'accent_rgb':rgb(accent),'limits':'base colours only, not all lit-frame pixels or device rendering'},indent=2)+'\n')
print('VERIFIED white body, unchanged green/lights/E200/assembly, black fine stripe and base contrast',contrast)
