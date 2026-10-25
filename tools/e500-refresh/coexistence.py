import json,sys
from pathlib import Path
base,current,out=map(Path,sys.argv[1:]);a=json.loads((base/'fingerprints.json').read_text());b={m['id']:m for m in json.loads((current/'fingerprints.json').read_text())}
changed={'set-'+k+'-head' for k in ['E500CK','MINGRI','STAR']};kept=[]
for m in a:
 if m['id'] in changed:continue
 n=b[m['id']];assert (base/m['payload']).read_bytes()==(current/n['payload']).read_bytes(),m['id'];kept.append(m['id'])
new=set(b)-{m['id'] for m in a};expected={'set-'+k+'Far-'+u for k in ['E500CK','MINGRI','STAR'] for u in ['head','car','tail']};assert new==expected,(new,expected)
(out/'coexistence.json').write_text(json.dumps({'status':'VERIFIED','baseline_commit':'41c00fa5','unchanged_old_models':len(kept),'changed_old_heads':sorted(changed),'new_far_models':sorted(new),'checks':['all other original vertex position/color/layer payload bytes identical','new names limited to three E500 far sets']},indent=2)+'\n')
print('VERIFIED coexistence:',len(kept),'old model payloads unchanged')
