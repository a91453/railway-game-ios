"""Compare the real complete position/normal/colour/layer payload of every old model."""
import hashlib,json,sys
from pathlib import Path

base,current,out=map(Path,sys.argv[1:4])
a=json.loads((base/'fingerprints.json').read_text())
b={m['id']:m for m in json.loads((current/'fingerprints.json').read_text())}
changed=set()
kept=[]
for m in a:
    assert m['id'] in b,('missing existing model',m['id'])
    n=b[m['id']]
    old=(base/m['payload']).read_bytes();new=(current/n['payload']).read_bytes()
    if m['id'] in changed:
        assert old!=new,('unexpected substitution absent',m['id'])
        continue
    assert old==new,('protected model payload changed',m['id'])
    kept.append({'id':m['id'],'sha256':hashlib.sha256(new).hexdigest(),'triangles':n['triangles']})
new=set(b)-{m['id'] for m in a}
expected={"emu800-"+r+s+f for r in ["ed","ema","ep","emb"] for s in ["","-reverse"] for f in ["","-far"]}
assert new==expected,('unexpected new model IDs',sorted(new))
out.mkdir(parents=True,exist_ok=True)
(out/'coexistence.json').write_text(json.dumps({'status':'VERIFIED','baseline_commit':sys.argv[4] if len(sys.argv)>4 else 'fba93033','unchanged_old_models':len(kept),'changed_old_models':sorted(changed),'new_models':sorted(new),'checks':['complete Float32 position/normal/colour/layer payload bytes identical for all other old models','E500CK/MINGRI/STAR all old components preserved','E1000 head preserved including reused far head','accepted E500 and EMU3000 direct model payload preserved'],'protected_payloads':kept},indent=2)+'\n')
print('VERIFIED coexistence:',len(kept),'complete old payloads preserved')
