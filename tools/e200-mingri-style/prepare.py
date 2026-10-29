"""Select actual exported units; prepare fixed-camera true-original comparisons.
FULL OUTPUT COMPARISON_BEFORE COMPARISON_AFTER
"""
import json,shutil,sys
from pathlib import Path
full,out,before,after=map(Path,sys.argv[1:5]);manifest=json.loads((full/'manifest.json').read_text())
units=['e200mingri-style-'+r+suffix for suffix in ['', '-far'] for r in ['head','car','tail']]
units+=['set-E200CK'+suffix+'-'+r for suffix in ['', 'Far'] for r in ['head','car','tail']]
if len(sys.argv)==5:
 out.mkdir(parents=True,exist_ok=True);(out/'models').mkdir(exist_ok=True)
 m=dict(manifest);m['models']=[v for v in manifest['models'] if v['id'] in units];m['model_count']=len(m['models'])
 for v in m['models']:shutil.copy2(full/v['native'],out/v['native'])
 (out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
# Called again after assembly/package to build same-ID comparison manifests.
if len(sys.argv)>5:
 m=json.loads((out/'manifest.json').read_text())
 for root,isnew in [(before,False),(after,True)]:
  root.mkdir(parents=True,exist_ok=True);(root/'models').mkdir(exist_ok=True);rows=[]
  for v in m['models']:
   own=v['id'].startswith(('e200mingri-','mingri-style-formation'))
   old=v['id'].startswith(('set-E200CK','original-e200ck-formation'))
   if not (own if isnew else old):continue
   row=dict(v)
   if not isnew:
    row['id']=row['id'].replace('set-E200CKFar-','e200mingri-style-')+'-far' if row['id'].startswith('set-E200CKFar-') else row['id'].replace('set-E200CK-','e200mingri-style-').replace('original-e200ck-formation','mingri-style-formation')
   shutil.copy2(out/v['native'],root/v['native']);rows.append(row)
  mm=dict(m);mm['models']=rows;mm['model_count']=len(rows);(root/'manifest.json').write_text(json.dumps(mm,indent=2)+'\n')
