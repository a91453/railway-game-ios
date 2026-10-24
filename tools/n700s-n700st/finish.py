#!/usr/bin/env python3
"""Render, package and hash the final native bytes for both paint variants."""
import argparse,hashlib,json,sys,zipfile
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont

def main(pipeline,root,commit):
    sys.path.insert(0,str(pipeline));from native_probe import decode
    from render_native import render,VIEWS
    from n700s_native import basis
    import trimesh
    root=Path(root)
    for variant in ('n700s','n700st'):
        dst=root/variant;ass=json.loads((dst/'assembly.json').read_text());rows=[];lookup={}
        for f in sorted((dst/'models').glob(f'railway-{variant}-?.m3dmodel')):
            t,c,_=decode(f.read_bytes());lookup[f.name]=(t,c);rows.append((f.stem,t,c,48))
        ts=[];cs=[]
        for placement in ass['placements']:
            t,c=lookup[placement['nativeModel']];t=t.copy()
            if placement['reversed']:t[:,:,:2]*=-1
            t[:,:,0]+=placement['translationX'];ts.append(t);cs.append(c)
        rows.append((f'railway-{variant}-source-ten-body-draft',np.concatenate(ts),np.concatenate(cs),5.5))
        for name,t,c,scale in rows:
            folder=dst/'previews'/name;folder.mkdir(parents=True,exist_ok=True)
            for view in VIEWS:render(t,c,view,scale=scale).save(folder/(view+'.png'))
            render(t,c,'right',scale=scale,silhouette=True).save(folder/'silhouette.png')
            white=c.copy();white[:,:,:3]=246;render(t,white,'isometric',scale=scale).save(folder/'white-isometric.png')
        overview=Image.new('RGB',(1400,1150),'#ECEEF6');d=ImageDraw.Draw(overview)
        d.text((35,20),f'{variant.upper()} • static native visual candidate',fill='#262C57')
        def paste(name,view,x,y,w,h):
            im=Image.open(dst/'previews'/name/(view+'.png'));im.thumbnail((w,h));overview.paste(im,(x+(w-im.width)//2,y+(h-im.height)//2),im)
        paste(f'railway-{variant}-a','isometric',0,50,1400,440)
        for i,letter in enumerate('bcde'):
            paste(f'railway-{variant}-{letter}','right',0,480+i*105,1400,100)
        paste(f'railway-{variant}-source-ten-body-draft','right',0,920,1400,155)
        d.text((35,1090),'Source order is a visual draft; rail plane and engineering dimensions unverified.',fill='#262C57')
        overview.save(dst/f'Railway_{variant.upper()}_Overview.png')
        previous=root/'repair-before'/variant/'models'/f'railway-{variant}-a.m3dmodel'
        original=(root/'source-body'/'previews'/f'railway-n700s-a'/'isometric.png')
        if previous.exists():
            old_t,old_c,_=decode(previous.read_bytes())
            original=root/'repair-before'/variant/'previews'/f'railway-{variant}-a'/'isometric.png'
            original.parent.mkdir(parents=True,exist_ok=True)
            render(old_t,old_c,'isometric',scale=48).save(original)
        if original.exists():
            before=Image.open(original).convert('RGBA');after=Image.open(dst/'previews'/f'railway-{variant}-a'/'isometric.png').convert('RGBA')
            comparison=Image.new('RGBA',(before.width*2,before.height),'white');comparison.paste(before,(0,0),before);comparison.paste(after,(before.width,0),after)
            comparison.save(dst/f'Railway_{variant.upper()}_Before_After.png')
        # Existing self-contained viewer is parameterized only by vehicle name.
        script=(pipeline/'make_viewer.py').read_text().replace('railway-n700s','railway-'+variant).replace('N700S',variant.upper())
        script=script.replace('Bogies/wheels and engineering scale unresolved.','Wheel gear is a provisional visual placement; engineering scale unresolved.')
        code=dst/'_make_viewer.py';code.write_text(script)
        local_renderer=dst/'render_delivery.py'
        local_renderer.write_text((pipeline/'render_delivery.py').read_text().replace('n700s',variant).replace('N700S',variant.upper()))
        import subprocess
        subprocess.run([sys.executable,str(code),str(dst)],check=True,env=__import__('os').environ|{'PYTHONPATH':str(pipeline),'PYTHONDONTWRITEBYTECODE':'1'})
        code.unlink();local_renderer.unlink()
        record={'producerCommit':commit,'variant':variant,'files':{}}
        for f in sorted(dst.rglob('*')):
            if f.is_file() and f.name not in ('source_record.json',) and f.suffix!='.zip':record['files'][str(f.relative_to(dst))]=hashlib.sha256(f.read_bytes()).hexdigest()
        (dst/'source_record.json').write_text(json.dumps(record,indent=2)+'\n')
        archive=dst/f'Railway_{variant.upper()}_Complete.zip'
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
            for f in sorted(dst.rglob('*')):
                if f.is_file() and f!=archive:z.write(f,f.relative_to(dst))
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None
            for name,sha in record['files'].items():assert hashlib.sha256(z.read(name)).hexdigest()==sha
        print(variant,len(rows),archive.stat().st_size)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--pipeline',type=Path,required=True);p.add_argument('--root',type=Path,required=True);p.add_argument('--producer-commit',required=True)
    a=p.parse_args();main(a.pipeline,a.root,a.producer_commit)
