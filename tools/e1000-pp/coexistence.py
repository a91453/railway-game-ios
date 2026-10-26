"""Compare the real complete position/normal/colour/layer payload of every old model."""
import hashlib,json,sys
from pathlib import Path

base,current,out=map(Path,sys.argv[1:])
a=json.loads((base/'fingerprints.json').read_text())
b={m['id']:m for m in json.loads((current/'fingerprints.json').read_text())}
changed={'set-pushPull-head','set-pushPullFar-head'}
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
expected={'e1000','e1000-far'}
assert new==expected,('unexpected new names',sorted(new),sorted(expected))
out.mkdir(parents=True,exist_ok=True)
(out/'coexistence.json').write_text(json.dumps({'status':'VERIFIED','baseline_commit':'61c6969c92bf1689f7dc1fcd6242c1dc74112e3a','unchanged_old_models':len(kept),'changed_old_models':sorted(changed),'new_models':sorted(new),'checks':['complete Float32 position/normal/colour/layer payload bytes identical for all other old models','E500CK/MINGRI/STAR all old components preserved','only two dedicated pushPull head LOD payloads change; all PP coaches preserved','accepted E500 and EMU3000 direct model payload preserved'],'protected_payloads':kept},indent=2)+'\n')
print('VERIFIED coexistence:',len(kept),'complete old payloads preserved')
