"""Contact graph from actual closed triangles, not declared attachment constants.
Uses segment/triangle intersections, contained vertices and <=12mm surface gap.
AABB is only a broad phase. Roots are the rail-contact wheel rims.
"""
import json, struct, sys
from pathlib import Path
import numpy as np

EPS=0.012

def decode(path):
    data=path.read_bytes(); n,size=struct.unpack_from('<II',data,8); start=16+(size+3)//4*4
    return np.array([[struct.unpack_from('<fff',data,start+i*52+4+j*16) for j in range(3)] for i in range(n)])

def intersections(origins, directions, triangles, segment=False):
    a,b,c=triangles[:,0],triangles[:,1],triangles[:,2]
    e1,e2=b-a,c-a
    h=np.cross(directions[:,None,:],e2); det=np.sum(e1*h,axis=2)
    inv=np.divide(1.,det,out=np.zeros_like(det),where=np.abs(det)>1e-10)
    s=origins[:,None,:]-a; u=np.sum(s*h,axis=2)*inv
    q=np.cross(s,e1); v=np.sum(directions[:,None,:]*q,axis=2)*inv
    t=np.sum(e2*q,axis=2)*inv
    valid=(np.abs(det)>1e-10)&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)
    if segment: return np.any(valid&(t>=-1e-6)&(t<=1.000001))
    return np.where(valid&(t>1e-7),t,np.inf)

def within(points,triangles):
    # Min point/triangle distance (projected face or one of its three edges).
    a,b,c=triangles[:,0],triangles[:,1],triangles[:,2]; n=np.cross(b-a,c-a); nn=np.sum(n*n,axis=1)
    d=np.sum((points[:,None,:]-a)*n,axis=2)/nn
    p=points[:,None,:]-d[:,:,None]*n; v0,v1=b-a,c-a; v2=p-a
    d00=np.sum(v0*v0,axis=1);d01=np.sum(v0*v1,axis=1);d11=np.sum(v1*v1,axis=1)
    d20=np.sum(v2*v0,axis=2);d21=np.sum(v2*v1,axis=2);den=d00*d11-d01*d01
    u=(d11*d20-d01*d21)/den;v=(d00*d21-d01*d20)/den
    if np.any((u>=0)&(v>=0)&(u+v<=1)&(d*d*nn<=EPS*EPS)): return True
    for e,f in [(a,b),(b,c),(c,a)]:
        edge=f-e; t=np.clip(np.sum((points[:,None,:]-e)*edge,axis=2)/np.sum(edge*edge,axis=1),0,1)
        delta=points[:,None,:]-e-t[:,:,None]*edge
        if np.any(np.sum(delta*delta,axis=2)<=EPS*EPS): return True
    return False

def contact(a,b):
    pa=np.unique(a.reshape(-1,3),axis=0);pb=np.unique(b.reshape(-1,3),axis=0)
    for q,t in [(a,b),(b,a)]:
        origins=q.reshape(-1,3);ends=np.roll(q,-1,axis=1).reshape(-1,3)
        if intersections(origins,ends-origins,t,True): return True
    if within(pa,b) or within(pb,a): return True
    # Vertex wholly inside another solid (e.g. a shaft inside its bearing).
    for ps,ts in [(pa,b),(pb,a)]:
        for p in ps[:1]:
            distances=intersections(p[None,:],np.array([[1.,0.231,0.137]]),ts)[0]
            hits=np.unique(np.round(distances[np.isfinite(distances)],6))
            if len(hits)%2: return True
    return False

def audit(root,write=True,mutation=False):
    manifest=json.loads((root/'manifest.json').read_text()); components=json.loads((root/'components.json').read_text());records=[]
    for m in manifest['models']:
        if m['category']!='section':continue
        triangles=decode(root/m['native']);parts=[]
        for p in components[m['id']]:
            ts=triangles[p['start_triangle']:p['start_triangle']+p['triangles']];points=ts.reshape(-1,3)
            if mutation and p['name']=='safety-valve':
                ts=ts.copy();ts[:,:,2]+=0.7;points=ts.reshape(-1,3)
            parts.append(dict(p,ts=ts,low=points.min(axis=0),high=points.max(axis=0)))
        links=[set() for _ in parts];edges=0
        for i,a in enumerate(parts):
            for j in range(i):
                b=parts[j]
                if np.any(a['low']>b['high']+EPS) or np.any(b['low']>a['high']+EPS):continue
                if contact(a['ts'],b['ts']):links[i].add(j);links[j].add(i);edges+=1
        reached={i for i,p in enumerate(parts) if p['role']=='wheel'}; todo=list(reached)
        while todo:
            for j in links[todo.pop()]-reached:reached.add(j);todo.append(j)
        detached=[p['name'] for i,p in enumerate(parts) if i not in reached]
        record={'id':m['id'],'triangle_contact_edges':edges,'components':len(parts),'connected_to_rail_wheels':len(reached),'detached':detached};records.append(record)
        print(json.dumps(record),flush=True)
    result={'status':'VERIFIED' if all(not x['detached'] for x in records) else 'FAILED','surface_tolerance_m':EPS,'method':'actual segment/triangle intersections, vertex/triangle proximity, contained vertices; AABB broadphase only','models':records}
    if write:(root/'support-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    assert result['status']=='VERIFIED','Disconnected equipment: see support-verification.json'
    return result

if __name__=='__main__':
    root=Path(sys.argv[1])
    if '--mutation' in sys.argv:
        try:audit(root,write=False,mutation=True)
        except AssertionError:
            (root/'support-mutation-verification.json').write_text(json.dumps({'status':'VERIFIED','mutation':'closed safety valve translated 0.7m upwards','result':'REJECTED by triangle contact graph'},indent=2)+'\n')
        else:raise AssertionError('Floating equipment escaped validation')
    else:audit(root)
