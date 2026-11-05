import json,math,sys,struct
from pathlib import Path
root=Path(sys.argv[1]);d=json.loads((root/'manifest.json').read_text());assert len(d['models'])==30
for m in d['models']:
 b=(root/m['native']).read_bytes();assert b[:4]==b'M3DM';n=struct.unpack_from('<I',b,8)[0];assert n==m['triangles'] and n<=15000
 assert (root/m['glb']).read_bytes()[:4]==b'glTF'
 assert len(m['views'])==14
 for v in m['views'].values():assert (root/v).read_bytes()[:8]==b'\x89PNG\r\n\x1a\n'
 for bay in m['metadata'].get('parking',[]):
  assert bay['usable_length']>=13.2 and bay['clear_width']>=3.16 and math.isclose(math.hypot(*bay['heading'][:2]),1)
 for k in ('entry','exit'):
  if k in m['metadata']:assert m['metadata'][k]['position'][2]==0
print('verified',len(d['models']),'models and',sum(len(m['views']) for m in d['models']),'PNGs')
