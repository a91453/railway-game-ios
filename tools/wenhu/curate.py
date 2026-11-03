from pathlib import Path
import json,shutil,sys
root=Path(sys.argv[1]);repo=Path(__file__).resolve().parents[2]
for fleet in ['val256','apm256']:
 out=root/fleet;out.mkdir(exist_ok=True)
 manifest=json.loads((root/'manifest.json').read_text());manifest['models']=[m for m in manifest['models'] if m['id'].startswith('wenhu-'+fleet+'-')];manifest['model_count']=len(manifest['models']);manifest['sets']=[]
 for m in manifest['models']:
  for key in ['native','glb','assembly_payload']:
   if key in m:
    dest=out/m[key];dest.parent.mkdir(exist_ok=True,parents=True);shutil.copy2(root/m[key],dest)
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 shutil.copy2(repo/'docs/art/wenhu/sources.json',out/'source-record.json')
 shutil.copy2(repo/f'docs/art/wenhu/{fleet}-status.json',out/'status.json')
 for role in ['a','b','formation']:
  (out/'sheets').mkdir(exist_ok=True);shutil.copy2(root/f'sheets/{fleet}-{role}.png',out/f'sheets/{fleet}-{role}.png')
