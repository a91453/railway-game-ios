#!/usr/bin/env python3
"""Private-input N700S / N700ST static native asset rebuild.

The five owner-supplied GLBs stay private. The model units are provisional source
units; the rail plane and engineering dimensions need real-world calibration.
"""
import argparse, importlib.util, json, math, sys
from collections import defaultdict
from pathlib import Path
import numpy as np

def load_pipeline(path):
    sys.path.insert(0,str(path))
    spec=importlib.util.spec_from_file_location('n700s_native',path/'n700s_native.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def box(center,size):
    cx,cy,cz=center;sx,sy,sz=np.array(size)/2
    v=np.array([[cx+dx*sx,cy+dy*sy,cz+dz*sz] for dx in (-1,1) for dy in (-1,1) for dz in (-1,1)])
    faces=[(0,2,3),(0,3,1),(4,5,7),(4,7,6),(0,1,5),(0,5,4),(2,6,7),(2,7,3),(0,4,6),(0,6,2),(1,3,7),(1,7,5)]
    return v[np.array(faces)][:,[0,2,1]]

def wheel(cx,cy,cz,r=.36,width=.11,segments=12):
    triangles=[]
    for i in range(segments):
        a=2*math.pi*i/segments;b=2*math.pi*(i+1)/segments
        q=lambda y,t:np.array([cx+r*math.cos(t),y,cz+r*math.sin(t)])
        lo,hi=cy-width/2,cy+width/2
        p0,p1,p2,p3=q(lo,a),q(lo,b),q(hi,b),q(hi,a)
        triangles.extend([[p0,p1,p2],[p0,p2,p3],[[cx,lo,cz],p1,p0],[[cx,hi,cz],p3,p2]])
    return np.array(triangles)[:,[0,2,1]]

def running_gear(length,cab=False):
    # Two provisional two-axle bogies; wheel tread bottom is the local z=0.
    # These positions are visual estimates, not certified bogie dimensions.
    parts=[]
    def add(t,color):parts.append((t,np.tile(np.array(color,dtype=np.uint8),(len(t),1))))
    for bx in (-length*.36,length*(.18 if cab else .36)):
        add(box((bx,0,.69),(2.05,1.9,.24)),[65,71,79,255])
        add(box((bx,0,.48),(1.65,1.47,.18)),[91,98,105,255])
        for ax in (bx-.55,bx+.55):
            add(box((ax,0,.37),(.16,1.95,.13)),[73,78,85,255])
            for side in (-1,1):add(wheel(ax,side*.98,.36),[43,49,57,255])
    return np.concatenate([p for p,c in parts]),np.concatenate([c for p,c in parts])

def close_surface(triangles, colors, thickness=.012):
    """Give each source surface fan a sealed thin back and boundary wall.

    The source contains open panels touching at vertices. A touching vertex
    with separate face fans must be split before adding the boundary walls;
    otherwise the apparent closure has four incident edges and is not a
    manifold. The tiny fan separation survives Float32 native serialization.
    """
    import trimesh
    mesh=trimesh.Trimesh(vertices=np.asarray(triangles).reshape(-1,3),
                         faces=np.arange(len(triangles)*3).reshape(-1,3),process=False)
    mesh.merge_vertices(digits_vertex=5)
    faces=mesh.faces.copy();vertices=mesh.vertices.tolist()
    incident=defaultdict(set);edge_faces=defaultdict(list)
    for face_index,face in enumerate(faces):
        for vertex in face:incident[int(vertex)].add(face_index)
        for a,b in zip(face,np.roll(face,-1)):
            edge_faces[tuple(sorted((int(a),int(b))))].append(face_index)
    if any(len(shared)>2 for shared in edge_faces.values()):
        raise ValueError('Source has a nonmanifold edge before closure')
    adjacent=defaultdict(lambda:defaultdict(set))
    for (a,b),shared in edge_faces.items():
        if len(shared)==2:
            for vertex in (a,b):
                adjacent[vertex][shared[0]].add(shared[1])
                adjacent[vertex][shared[1]].add(shared[0])
    split_vertices=0
    for vertex,face_ids in incident.items():
        pending=set(face_ids);first=True;ordinal=0
        while pending:
            start=pending.pop();fan=[start];queue=[start]
            while queue:
                for nxt in adjacent[vertex][queue.pop()]:
                    if nxt in pending:
                        pending.remove(nxt);queue.append(nxt);fan.append(nxt)
            if first:
                first=False;continue
            ordinal+=1
            normal=mesh.face_normals[fan].mean(axis=0)
            normal/=max(np.linalg.norm(normal),1e-12)
            new=len(vertices)
            vertices.append((np.asarray(vertices[vertex])+normal*(.0002*ordinal)).tolist())
            split_vertices+=1
            for face_index in fan:faces[face_index][faces[face_index]==vertex]=new
    surface=trimesh.Trimesh(vertices=np.asarray(vertices),faces=faces,process=False)
    if not surface.is_winding_consistent:raise ValueError('Source surface winding is inconsistent')
    directed=faces[:,[[0,1],[1,2],[2,0]]].reshape(-1,2)
    _,first,count=np.unique(np.sort(directed,axis=1),axis=0,return_index=True,return_counts=True)
    boundary=directed[first[count==1]];boundary_colors=np.asarray(colors)[first[count==1]//3]
    normals=surface.vertex_normals.copy()
    normals[np.linalg.norm(normals,axis=1)<1e-10]=[0,0,1]
    normals/=np.linalg.norm(normals,axis=1)[:,None]
    n=len(vertices)
    points=np.vstack([surface.vertices,surface.vertices-thickness*normals])
    back=faces[:,[0,2,1]]+n
    sides=np.asarray([[a,a+n,b+n] for a,b in boundary]+[[a,b+n,b] for a,b in boundary],dtype=int)
    all_faces=np.vstack([faces,back,sides])
    all_colors=np.concatenate([colors,colors,boundary_colors,boundary_colors])
    closed=points[all_faces].astype(np.float32)
    check=trimesh.Trimesh(vertices=closed.reshape(-1,3),
                          faces=np.arange(len(closed)*3).reshape(-1,3),process=False)
    check.merge_vertices(digits_vertex=5)
    if not check.is_watertight or not check.is_winding_consistent:
        raise ValueError('Closed native readback failed manifold checks')
    return closed,all_colors,{'splitFanVertices':split_vertices,'boundaryEdges':len(boundary),
                              'shellTriangles':len(closed),'shellThicknessSourceUnits':thickness}

def rebuild(pipe,source,out,producer):
    original=out/'source-body'
    if not (original/'assembly.json').exists():pipe.convert_set(source,original,producer)
    for variant in ('n700s','n700st'):
        target=out/variant;target.mkdir(exist_ok=True)
        (target/'models').mkdir(exist_ok=True)
        rows=[];units={}
        for letter in pipe.SOURCE_FILES:
            old=original/'models'/f'railway-n700s-{letter}.m3dmodel'
            t,c,meta=pipe.decode(old.read_bytes());c=c[:,0].copy()
            # Existing N700S paint is retained exactly, before adding the running gear.
            if variant=='n700st':
                palette={tuple(pipe.rgb('stripe')):[231,142,42,255],
                         tuple(pipe.rgb('body')):[246,244,238,255],
                         tuple(pipe.rgb('roof')):[205,207,207,255],
                         tuple(pipe.rgb('skirt')):[153,157,159,255]}
                c=np.array([palette.get(tuple(color),color) for color in c],dtype=np.uint8)
            # The source body's bottom begins at z=0. New wheel tread defines z=0.
            t=t.copy();t[:,:,2]+=.74
            t,c,closure=close_surface(t,c)
            length=np.ptp(t[:,:,0]);gear,gc=running_gear(length,cab=letter=='a')
            t=np.concatenate((t,gear));c=np.concatenate((c,gc))
            meta=dict(meta);meta.update(kind=f'Railway {variant.upper()} static visual candidate',producerCommit=producer,
                wheelRailPlane='provisional wheel tread z=0; source units, not certified metres',
                visualChanges='two bogies, eight supported wheels per unit; N700ST has logo-free ivory/amber HSR-inspired paint' if variant=='n700st' else 'two bogies, eight supported wheels per unit; original N700S paint retained',
                surfaceClosure=closure,
                limitations=['engineering dimensions and exact bogie anchors unverified','complete 16-car formation unverified','no animation'])
            path=target/'models'/f'railway-{variant}-{letter}.m3dmodel'
            stats=pipe.write_native(path,t,c,meta);rows.append(stats);units[letter]=(t,c)
        placements=[];arrays=[];colors=[];end=0
        for slot,index in enumerate(pipe.SOURCE_ORDER,1):
            letter=chr(ord('a')+abs(index)-1);t,c=units[letter];t=t.copy()
            if index<0:t[:,:,:2]*=-1
            length=np.ptp(t[:,:,0]);center=-(end+length/2);t[:,:,0]+=center;end+=length+.4
            arrays.append(t);colors.append(c)
            placements.append(dict(slot=slot,unit=letter,reversed=index<0,translationX=float(center),rotationDegrees=180 if index<0 else 0,gapSourceUnits=.4,nativeModel=f'railway-{variant}-{letter}.m3dmodel'))
        all_t=np.concatenate(arrays);all_c=np.concatenate(colors);shift=(all_t[:,:,0].min()+all_t[:,:,0].max())/2;all_t[:,:,0]-=shift
        for p in placements:p['translationX']-=float(shift)
        aggregate=dict(kind='SOURCE_10_BODY_VISUAL_DRAFT_NOT_REAL_FORMATION',producerCommit=producer,variant=variant,placements=placements,
                       triangles=len(all_t),bounds=np.array([all_t.min((0,1)),all_t.max((0,1))]).tolist(),sourceOrder=pipe.SOURCE_ORDER,
                       nativeAssembly='instantiate five individual M3DM units with placement transforms')
        import trimesh
        mesh=trimesh.Trimesh(vertices=all_t.reshape(-1,3)@pipe.basis('+x'),faces=np.arange(len(all_t)*3).reshape(-1,3),process=False)
        mesh.visual.face_colors=all_c;trimesh.Scene(mesh).export(target/'models'/f'railway-{variant}-source-ten-body-draft.glb')
        pipe.write_json(target/'assembly.json',aggregate);pipe.write_json(target/'conversion_report.json',dict(models=rows,assembly=aggregate))
        print(variant,[(r['id'],r['triangles']) for r in rows])

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--pipeline',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--producer-commit',required=True)
    a=p.parse_args();rebuild(load_pipeline(a.pipeline),a.source,a.out,a.producer_commit)
