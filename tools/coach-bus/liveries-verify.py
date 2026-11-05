import json,sys,struct
from pathlib import Path
from PIL import Image
root=Path(sys.argv[1]);d=json.loads((root/'manifest.json').read_text());models=d['models'];assert len(models)==16
assert len({m['livery_id'] for m in models})==8
for m in models:
 b=(root/m['native']).read_bytes();assert b[:4]==b'M3DM' and struct.unpack_from('<I',b,8)[0]==m['triangles']
 assert (root/m['glb']).read_bytes()[:4]==b'glTF'
 assert len(m['views'])==14
 for v in m['views'].values():
  image=Image.open(root/v);assert image.mode=='RGBA' and image.getchannel('A').getextrema()==(0,255)
for state in ('day','night'):assert (root/('fleet-'+state+'.png')).exists()
print('verified 16 models, 224 transparent views, 2 fleet sheets')
