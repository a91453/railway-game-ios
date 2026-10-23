"""Show the geometry audit rejects missing faces, flipped faces and detached glass."""
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
root=Path(sys.argv[1]).resolve()
audit=Path(__file__).with_name('geometry-audit.mjs').resolve()
manifest=json.loads((root/'manifest.json').read_text())
results=[]
for record in [m for m in manifest['models'] if m['id'] in ['blue-seven-leading','blue-seven-middleOne']]:
 target=record['native'];original=(root/target).read_bytes()
 start=16+((struct.unpack_from('<I',original,12)[0]+3)//4)*4
 for defect in ['missing-face','reversed-face','floating-glass']:
  with tempfile.TemporaryDirectory(prefix='lrt-mutation-') as temp:
   out=Path(temp)
   shutil.copytree(root/'models',out/'models')
   (out/'manifest.json').write_text(json.dumps(manifest))
   blob=bytearray(original)
   if defect=='missing-face':
    del blob[start:start+52]
    struct.pack_into('<I',blob,8,struct.unpack_from('<I',blob,8)[0]-1)
   elif defect=='reversed-face':
    a=bytes(blob[start+4:start+20]);b=bytes(blob[start+20:start+36])
    blob[start+4:start+20]=b;blob[start+20:start+36]=a
   else:
    # Exact palette glass of the current native; move all vertices as closed
    # pieces, so edge closure alone cannot catch this visible defect.
    glass=tuple(map(int,json.loads((root/'geometry-verification.json').read_text())['glass_rgba'].split(',')))
    family={tuple(v if i==3 else int(v*f+0.5) for i,v in enumerate(glass)) for f in [1,.92,.80,.70,.86]}
    for triangle in range(struct.unpack_from('<I',blob,8)[0]):
     for vertex in range(3):
      at=start+triangle*52+4+vertex*16
      if tuple(blob[at+12:at+16]) in family:
       y=struct.unpack_from('<f',blob,at+4)[0]
       if abs(y)>1.1:struct.pack_into('<f',blob,at+4,y+(0.3 if y>0 else -0.3))
   (out/target).write_bytes(blob)
   run=subprocess.run(['node',str(audit),str(out)],capture_output=True,text=True)
   assert run.returncode!=0,f'Audit accepted {defect}'
   if defect=='floating-glass':
    assert 'unsupported glazing' in run.stderr,'Detached closed glass must fail its support ray, not closure: '+run.stderr[-2400:]
   results.append({'id':record['id'],'defect':defect,'rejected':True,'diagnostic':run.stderr[-1800:]})
(root/'mutation-verification.json').write_text(json.dumps({'status':'VERIFIED','mutants':results},indent=2)+'\n')
print('VERIFIED actual-triangle mutations: missing face, inverted face, unsupported glass rejected')
