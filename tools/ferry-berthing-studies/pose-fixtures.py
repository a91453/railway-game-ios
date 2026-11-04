import base64,json,struct,sys
from pathlib import Path
from produce import Mesh,posed
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());fixtures=[]
for m in manifest['models']:
 j=m['connectors'].get('joint')
 if not j or not m['id'].endswith('-near'):continue
 b=(root/m['native']).read_bytes();count,size=struct.unpack_from('<II',b,8);at=16+(size+3)//4*4;mesh=Mesh()
 for i in range(count):
  flags=struct.unpack_from('<I',b,at+i*52)[0];v=[struct.unpack_from('<fffI',b,at+i*52+4+k*16) for k in range(3)];mesh.t.append(([p[:3] for p in v],v[0][3],flags))
 for value in [j['limit'][0],j['rest'],j['limit'][1]]:
  result=posed(mesh,m['connectors'],value);positions=b''.join(struct.pack('<fff',*p) for v,c,g in result for p in v)
  fixtures.append({'id':m['id'],'value':value,'positions_f32_base64':base64.b64encode(positions).decode()})
(root/'pose-fixtures.json').write_text(json.dumps(fixtures,separators=(',',':'))+'\n');print('Independent Python pose fixtures',len(fixtures))
