#!/usr/bin/env python3
"""Render, package and hash selected native paint variants."""
import argparse,hashlib,json,shutil,sys,zipfile
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont

def main(pipeline,root,commit,variants):
    sys.path.insert(0,str(pipeline));from native_probe import decode
    from render_native import render,VIEWS
    from n700s_native import basis
    import trimesh
    root=Path(root)
    for variant in variants:
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
        overview=Image.new('RGB',(1600,1580),'#ECEEF6');d=ImageDraw.Draw(overview)
        font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',32)
        small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22)
        d.text((45,26),f'{variant.upper()}  /  static native visual candidate',fill='#262C57',font=font)
        def paste(name,view,x,y,w,h):
            im=Image.open(dst/'previews'/name/(view+'.png')).convert('RGBA')
            bbox=im.getbbox()
            if bbox:im=im.crop(bbox)
            im.thumbnail((w,h),Image.Resampling.LANCZOS)
            overview.paste(im,(x+(w-im.width)//2,y+(h-im.height)//2),im)
        paste(f'railway-{variant}-a','isometric',70,90,1460,530)
        d.text((45,632),'A / driving end',fill='#262C57',font=small)
        for i,letter in enumerate('bcde'):
            y=680+i*150
            d.text((45,y+42),letter.upper(),fill='#262C57',font=font)
            paste(f'railway-{variant}-{letter}','right',145,y,1400,130)
        d.text((45,1295),'Source 10-body visual draft',fill='#262C57',font=small)
        paste(f'railway-{variant}-source-ten-body-draft','right',45,1330,1510,160)
        d.text((45,1530),'Rail plane and engineering dimensions unverified.',fill='#262C57',font=small)
        overview.save(dst/f'Railway_{variant.upper()}_Overview.png')
        previous=root/'repair-before'/variant/'models'/f'railway-{variant}-a.m3dmodel'
        original=(root/'source-body'/'previews'/f'railway-n700s-a'/'isometric.png')
        if variant=='n700s-g':
            previous=root/'n700s'/'models'/'railway-n700s-a.m3dmodel'
            snapshot=dst/'revision-before'
            snapshot.mkdir(parents=True,exist_ok=True)
            for f in sorted((root/'n700s'/'models').glob('railway-n700s-?.m3dmodel')):
                shutil.copy2(f,snapshot/f.name)
            old_t,old_c,_=decode(previous.read_bytes())
            original=snapshot/'railway-n700s-a-isometric.png'
            render(old_t,old_c,'isometric',scale=48).save(original)
            before_side=render(old_t,old_c,'right',scale=48)
            after_side=Image.open(dst/'previews'/f'railway-{variant}-a'/'right.png').convert('RGBA')
            after_iso=Image.open(dst/'previews'/f'railway-{variant}-a'/'isometric.png').convert('RGBA')
            before_iso=Image.open(original).convert('RGBA')
            comparison=Image.new('RGBA',(before_iso.width*2,before_iso.height*2),'white')
            for im,pos in ((before_iso,(0,0)),(after_iso,(before_iso.width,0)),
                           (before_side,(0,before_iso.height)),(after_side,(before_iso.width,before_iso.height))):
                comparison.paste(im,pos,im)
            labels=ImageDraw.Draw(comparison)
            label_font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22)
            labels.text((24,20),'ORIGINAL N700S  /  #2B3356',fill='#262C57',font=label_font)
            labels.text((before_iso.width+24,20),'N700S-G  /  #1D4A44',fill='#1D4A44',font=label_font)
            comparison.save(dst/'Railway_N700S-G_Livery_Before_After.png')
        elif previous.exists():
            snapshot=dst/'revision-before'
            shutil.copytree(root/'repair-before'/variant,snapshot,dirs_exist_ok=True)
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
        script=script.replace(
            "function geometry(){let m=MODELS[+select.value||0],v=m.triangles.flat(),lo=[0,1,2].map(k=>Math.min(...v.map(p=>p[k]))),hi=[0,1,2].map(k=>Math.max(...v.map(p=>p[k])));return {m,lo,hi,center:lo.map((a,k)=>(a+hi[k])/2)};}",
            "function geometry(){let m=MODELS[+select.value||0],lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(const t of m.triangles)for(const p of t)for(let k=0;k<3;k++){lo[k]=Math.min(lo[k],p[k]);hi[k]=Math.max(hi[k],p[k]);}return {m,lo,hi,center:lo.map((a,k)=>(a+hi[k])/2)};}")
        script=script.replace(
            "let proj=m.triangles.map(t=>t.map(project)),v=proj.flat(),sx=Math.max(...v.map(p=>p[0]))-Math.min(...v.map(p=>p[0])),sz=Math.max(...v.map(p=>p[1]))-Math.min(...v.map(p=>p[1]));",
            "let proj=m.triangles.map(t=>t.map(project)),xl=Infinity,xh=-Infinity,zl=Infinity,zh=-Infinity;for(const t of proj)for(const p of t){xl=Math.min(xl,p[0]);xh=Math.max(xh,p[0]);zl=Math.min(zl,p[1]);zh=Math.max(zh,p[1]);}let sx=xh-xl,sz=zh-zl;")
        if 'm.triangles.flat()' in script or 'Math.max(...v.map' in script:
            raise ValueError('Large formation viewer still uses spread extrema')
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
    p.add_argument('--variants',nargs='+',choices=('n700s','n700st','n700s-g'),default=('n700s','n700st'))
    a=p.parse_args();main(a.pipeline,a.root,a.producer_commit,a.variants)
