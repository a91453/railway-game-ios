#!/usr/bin/env python3
"""Independent final-file checks for the static native delivery."""
import argparse,hashlib,json,sys,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
import trimesh
from build import box,wheel as wheel_primitive

def main(root,pipeline):
    for primitive,center in [(box((0,0,0),(2,2,2)),np.zeros(3)),(wheel_primitive(0,0,.36),np.array([0,0,.36]))]:
        normal=np.cross(primitive[:,1]-primitive[:,0],primitive[:,2]-primitive[:,0])
        midpoint=primitive.mean(axis=1)
        assert (np.sum(normal*(midpoint-center),axis=1)>0).all()
    sys.path.insert(0,str(pipeline));from native_probe import decode
    report={}
    for variant in ('n700s','n700st'):
        folder=root/variant;assembly=json.loads((folder/'assembly.json').read_text());rows=[];stats=[]
        assert len(assembly['placements'])==10
        for f in sorted((folder/'models').glob(f'railway-{variant}-?.m3dmodel')):
            t,c,meta=decode(f.read_bytes());rgba=c[:,0];bounds=np.array([t.min((0,1)),t.max((0,1))]);assert len(t)<15000
            # Wheel tread reaches local rail plane, and each of two bogies has four wheels.
            wheel=np.all(rgba[:,:3]==[43,49,57],axis=1);assert wheel.sum()==384,(f,wheel.sum())
            assert abs(t[:,:,2].min())<2e-5,(f,t[:,:,2].min())
            assert (np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)>1e-10).all()
            assert len({tuple(x) for x in rgba})>=6
            m=trimesh.load(f.with_suffix('.glb'),force='mesh');assert len(m.faces)==len(t)
            assert np.isfinite(m.vertices).all()
            assert bounds[0,0]<-10 and bounds[1,0]>10
            rows.append(f.name);stats.append(dict(model=f.name,triangles=len(t),bounds=bounds.tolist(),wheelTriangles=int(wheel.sum()),nativeReadback=True,glbImport=True))
        for placement in assembly['placements']:
            assert placement['nativeModel'] in rows
            assert placement['rotationDegrees'] in (0,180)
        images=list((folder/'previews').glob('**/*.png'));assert len(images)==54,len(images)
        for f in images:
            with Image.open(f) as im:
                im.load();assert im.mode=='RGBA';alpha=np.asarray(im.getchannel('A'))
                assert alpha.min()==0 and alpha.max()==255
                assert alpha[0].max()==alpha[-1].max()==alpha[:,0].max()==alpha[:,-1].max()==0,f
        record=json.loads((folder/'source_record.json').read_text());assert record['files']
        for name,digest in record['files'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,name
        archive=folder/f'Railway_{variant.upper()}_Complete.zip'
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None
            for name,digest in record['files'].items():assert hashlib.sha256(z.read(name)).hexdigest()==digest,name
        report[variant]=dict(models=stats,pngs=len(images),zipFiles=len(record['files']),zipSHA256=hashlib.sha256(archive.read_bytes()).hexdigest(),staticOnly=True)
    (root/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:{'models':len(v['models']),'pngs':v['pngs'],'zipFiles':v['zipFiles']} for k,v in report.items()}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--pipeline',type=Path,required=True);a=p.parse_args();main(a.root,a.pipeline)
