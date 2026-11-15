"""Count pairs of faces of different materials on nearly the same plane
(0.5 mm to 5 cm apart, bounding boxes overlapping) in each GLB of the
current folder: a rough count of where the map may flicker. It counts too
many (bounding boxes), never too few.

    cd <revision folder> && python3 -I <repo>/tools/hk-landmarks/coplanar_check.py

Needs numpy.
"""
import json,struct,glob,numpy as np,sys
def load(f):
    d=open(f,'rb').read(); n=struct.unpack_from('<I',d,12)[0]; j=json.loads(d[20:20+n]); b=d[20+n+8:]
    T=[];M=[]
    for m in j['meshes']:
        for p in m['primitives']:
            a=j['accessors'][p['attributes']['POSITION']]; bv=j['bufferViews'][a['bufferView']]
            P=np.frombuffer(b,np.float32,a['count']*3,bv.get('byteOffset',0)+a.get('byteOffset',0)).reshape(-1,3)
            if 'indices' in p:
                ia=j['accessors'][p['indices']]; ib=j['bufferViews'][ia['bufferView']]
                dt={5125:np.uint32,5123:np.uint16}[ia['componentType']]
                I=np.frombuffer(b,dt,ia['count'],ib.get('byteOffset',0)+ia.get('byteOffset',0)).reshape(-1,3)
            else: I=np.arange(len(P)).reshape(-1,3)
            T.append(P[I]); M+= [p['material']]*len(I)
    return np.concatenate(T),np.array(M)
for f in sorted(glob.glob('*.glb')):
    T,M=load(f); n=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); a=np.linalg.norm(n,axis=1); ok=a>1e-6; T,M,n,a=T[ok],M[ok],n[ok]/a[ok,None],a[ok]
    d=(n*T[:,0]).sum(1); c=T.mean(1); lo=T.min(1); hi=T.max(1)
    # bucket by rounded normal
    key=np.round(n*20).astype(int); bad=0; pairs=0
    from collections import defaultdict
    g=defaultdict(list)
    for i,k in enumerate(map(tuple,key)): g[k].append(i)
    for k,idx in g.items():
        idx=np.array(idx)
        if len(idx)<2: continue
        order=idx[np.argsort(d[idx])]
        dd=d[order]
        for x in range(len(order)):
            y=x+1
            while y<len(order) and dd[y]-dd[x]<0.05:
                i,j=order[x],order[y]
                if dd[y]-dd[x]>0.0005 and M[i]!=M[j] and (lo[i]<hi[j]-0.05).all() is not None and np.all(lo[i][:]<=hi[j]) and np.all(lo[j]<=hi[i]):
                    # overlap on plane (bbox) with offset 0.5mm-5cm
                    bad+=1
                y+=1
    print(f,len(T),'near-coplanar overlapping diff-material pairs (0.5mm–5cm):',bad)
