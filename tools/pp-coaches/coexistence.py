"""Compare the real complete position/normal/colour/layer payload of every old model."""
import hashlib,json,sys
from pathlib import Path

base,current,out=map(Path,sys.argv[1:])
a=json.loads((base/'fingerprints.json').read_text())
b={m['id']:m for m in json.loads((current/'fingerprints.json').read_text())}
changed={'set-pushPull-car'}
kept=[]
for m in a:
    assert m['id'] in b,('missing existing model',m['id'])
    n=b[m['id']]
    old=(base/m['payload']).read_bytes();new=(current/n['payload']).read_bytes()
    if m['id'] in changed:
        assert old!=new,('PP substitution absent',m['id'])
        continue
    assert old==new,('protected model payload changed',m['id'])
    kept.append({'id':m['id'],'sha256':hashlib.sha256(new).hexdigest(),'triangles':n['triangles']})
new=set(b)-{m['id'] for m in a}
expected={'pp-'+r+s for r in ['ppm2500','pph1300','ppc1400','ppt1000'] for s in ['', '-far']}
expected|={'set-pushPullFar-head','set-pushPullFar-car'}
assert new==expected,('unexpected new names',sorted(new),sorted(expected))
assert (current/b['set-pushPullFar-head']['payload']).read_bytes()==(base/next(m['payload'] for m in a if m['id']=='set-pushPull-head')).read_bytes(),'E1000 far head differs from existing E1000'
out.mkdir(parents=True,exist_ok=True)
(out/'coexistence.json').write_text(json.dumps({'status':'VERIFIED','baseline_commit':'c005788c778d0743291f0c724d1336c668078385','unchanged_old_models':len(kept),'changed_old_models':sorted(changed),'new_models':sorted(new),'checks':['complete Float32 position/normal/colour/layer payload bytes identical for all other old models','E500CK/MINGRI/STAR all old components preserved','E1000 head preserved including reused far head','accepted E500 and EMU3000 direct model payload preserved'],'protected_payloads':kept},indent=2)+'\n')
print('VERIFIED coexistence:',len(kept),'complete old payloads preserved')
