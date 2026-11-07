#!/usr/bin/env python3
"""Standalone Liujia study. Native coordinates: +x along yard, +y left, +z up (m)."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

HERE = Path(__file__).parent
ORIGIN = (121.042793, 24.798603)
BEARING = math.radians(131.5)  # OSM yard axis, clockwise from north
GAUGE = 1.435
SHED_Y = -106.0
SHED_TRACKS = (-114.7,-108.9,-103.1,-97.3)
TRAIN_CENTRES = [(255.0, -108.9), (270.0, 7.0), (275.0, 24.0)]
TRAIN_UNITS = ('cab',) + ('middle', 'middle', 'panto', 'middle', 'middle', 'middle', 'middle', 'panto', 'middle', 'middle') + ('tail',)
TRAIN_X = (139.7, 114.3, 88.9, 63.5, 38.1, 12.7, -12.7, -38.1, -63.5, -88.9, -114.3, -139.7)
COLOURS = {'ground': 0xE1E6E0, 'ballast': 0xA9ADA9, 'rail': 0x848B94,
           'wall': 0xC9CCD5, 'roof': 0xAEB8C2, 'steel': 0x8A9099,
           'glass': 0xA9C6D3, 'walk': 0xD8D6CA, 'dark': 0x2B2F36,
           'wire': 0x747B85, 'yellow': 0xFFC86B, 'light': 0xFFF0BB}

def projected(point):
    east = (point[0]-ORIGIN[0])*101073
    north = (point[1]-ORIGIN[1])*110783
    return (east*math.sin(BEARING)+north*math.cos(BEARING),
            -east*math.cos(BEARING)+north*math.sin(BEARING))

class Mesh:
    def __init__(self): self.triangles=[]
    def tri(self, a,b,c,color,glow=0): self.triangles.append((int(glow),[(a,color),(b,color),(c,color)]))
    def quad(self,a,b,c,d,color,glow=0):
        self.tri(a,b,c,color,glow);self.tri(a,c,d,color,glow)
    def box(self,x,y,z,dx,dy,dz,color,glow=0):
        a=(x-dx/2,y-dy/2,z);b=(x+dx/2,y-dy/2,z);c=(x+dx/2,y+dy/2,z);d=(x-dx/2,y+dy/2,z)
        e=(a[0],a[1],z+dz);f=(b[0],b[1],z+dz);g=(c[0],c[1],z+dz);h=(d[0],d[1],z+dz)
        for face in ((d,c,b,a),(e,f,g,h),(a,b,f,e),(b,c,g,f),(c,d,h,g),(d,a,e,h)):
            self.quad(*face,color,glow)
    def segment(self,a,b,width,z,height,color):
        dx=b[0]-a[0];dy=b[1]-a[1];norm=math.hypot(dx,dy)
        if norm<0.01:return
        px=-dy/norm*width/2;py=dx/norm*width/2
        q=[(a[0]-px,a[1]-py),(b[0]-px,b[1]-py),(b[0]+px,b[1]+py),(a[0]+px,a[1]+py)]
        self.prism(q,z,height,color)
    def prism(self,poly,z,h,color):
        if len(poly)<3:return
        for i in range(1,len(poly)-1):self.tri((poly[0][0],poly[0][1],z+h),(poly[i][0],poly[i][1],z+h),(poly[i+1][0],poly[i+1][1],z+h),color)
        for i,p in enumerate(poly):
            q=poly[(i+1)%len(poly)]
            self.quad((p[0],p[1],z),(q[0],q[1],z),(q[0],q[1],z+h),(p[0],p[1],z+h),color)
    def add(self,other,ox=0,oy=0,oz=0):
        for flag,points in other.triangles:
            self.triangles.append((flag,[((p[0]+ox,p[1]+oy,p[2]+oz),col) for p,col in points]))

def rail(m,a,b):
    m.segment(a,b,2.4,0.04,0.12,COLOURS['ballast'])
    dx=b[0]-a[0];dy=b[1]-a[1];n=math.hypot(dx,dy)
    if n<0.01:return
    nx=-dy/n;ny=dx/n
    for side in (-1,1):
        off=side*GAUGE/2
        m.segment((a[0]+nx*off,a[1]+ny*off),(b[0]+nx*off,b[1]+ny*off),0.075,0.18,0.11,COLOURS['rail'])

def load_native(path):
    data=path.read_bytes()
    if data[:4]!=b'M3DM':raise ValueError(path)
    n,plen=struct.unpack_from('<II',data,8);start=16+(plen+3)//4*4
    if len(data)!=start+n*52:raise ValueError('M3DM length')
    m=Mesh()
    for i in range(n):
        off=start+i*52;flag=struct.unpack_from('<I',data,off)[0];pts=[]
        for j in range(3):
            x,y,z,color=struct.unpack_from('<fffI',data,off+4+j*16);pts.append(((x,y,z),color))
        m.triangles.append((flag,pts))
    return m

def write_native(path,mesh,source):
    provenance=json.dumps({'asset':{'generator':'thsr-liujia-depot-studies','version':'1'},'extras':source},separators=(',',':')).encode()
    out=bytearray(b'M3DM'+struct.pack('<HHII',1,0,len(mesh.triangles),len(provenance))+provenance)
    out.extend(bytes((-len(provenance))%4))
    for flag,points in mesh.triangles:
        out.extend(struct.pack('<I',flag))
        for p,color in points:out.extend(struct.pack('<fffI',*p,color))
    path.write_bytes(out)

def scene(osm,units,shared,far=False,night=False):
    m=Mesh();c=COLOURS
    m.box(265,0,-0.32,650,300,0.28,c['ground'])
    # OSM geometry remains visible; polygons and rails are projected, not redrawn by eye.
    for way in osm['ways']:
        tag=way['tags'];points=[projected(p) for p in way['points']]
        if tag.get('landuse')=='railway':
            m.prism(points[:-1],-0.15,0.045,0xCBD6CB)
        if tag.get('railway')=='rail' and tag.get('service') in ('yard','siding'):
            for a,b in zip(points,points[1:]):
                if all(-65<=p[0]<=580 and -145<=p[1]<=145 for p in (a,b)):rail(m,a,b)
        if tag.get('building')=='depot':
            height=5.5 if far else 6.5 # No OSM height; illustrative.
            m.prism(points[:-1],0,height,c['wall'])
            m.prism(points[:-1],height,0.18,c['roof'])
    # Four-track long inspection hall: conjectural length and function, situated within OSM yard.
    shed_x=255; shed_y=SHED_Y; shed_len=324; shed_width=24.6
    for y in SHED_TRACKS:
        rail(m,(shed_x-shed_len/2+6,y),(shed_x+shed_len/2-6,y))
        if not far:
            for side in (-2.15,2.15):
                m.box(shed_x,y+side,0.28,shed_len-8,0.8,1.30,c['walk'])
                m.box(shed_x,y+side,1.58,shed_len-8,0.08,0.62,c['yellow'])
    for y in (shed_y-shed_width/2,shed_y+shed_width/2):
        m.box(shed_x,y,0, shed_len,0.36,7.8,c['wall'])
    for x in (shed_x-shed_len/2,shed_x+shed_len/2):
        for y in [shed_y-shed_width/2+i*shed_width/4 for i in range(5)]:
            m.box(x,y,0,0.42,0.36,8.5,c['steel'])
    if far:
        m.box(shed_x,shed_y,8.5,shed_len+0.8,shed_width+1,0.3,c['roof'])
    else:
        for y in (shed_y-11.8,shed_y+11.8):m.box(shed_x,y,8.5,shed_len+0.8,1.8,0.3,c['roof'])
        for x in range(105,411,24):m.box(x,shed_y,8.5,0.25,shed_width,0.22,c['steel'])
    # Inspection hall and outdoor sidings have contact wire above the 700T pantograph.
    for y in (*SHED_TRACKS,7,24):
        m.box(255,y,5.65,510 if y>0 else shed_len-12,0.035,0.035,c['wire'])
    for x in range(110,461,55):
        for y in (-123,38):m.box(x,y,0,0.28,0.28,7.3,c['steel'])
        m.box(x,-42.5,7.15,0.20,161,0.20,c['steel'])
        if night:
            for y in (-108.9,7,24):m.box(x,y,6.9,0.65,0.65,0.13,c['light'],1)
    # The 1,067-mm shared wash piece cannot be reused on this standard-gauge track.
    m.box(440,-127,0,1.4,0.45,7.8,c['steel']);m.box(440,-121,0,1.4,0.45,7.8,c['steel'])
    m.box(440,-124,7.8,2.4,6.45,0.4,c['roof']);rail(m,(435,-124),(445,-124))
    m.add(shared['office'],20,-119)
    m.add(shared['gate'],520,-132)
    m.add(shared['guardHouse'],528,-129)
    m.box(74,-122,0,14,10,5,c['wall']);m.box(74,-122,5,14.4,10.4,0.25,c['roof']) # substation estimate
    for x in range(-20,551,4):m.add(shared['fence'],x,-143)
    for x,y in TRAIN_CENTRES:
        for unit,cx in zip(TRAIN_UNITS,TRAIN_X):m.add(units[unit],x+cx,y,0.29)
    return m

def main():
    p=argparse.ArgumentParser();p.add_argument('--assets',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    osm=json.loads((HERE/'osm_geometry.json').read_text())
    base=a.assets/'game-art-previews/docs/art/train-shape-refresh-2026-10-24/revision-10/models'
    units={};hashes={}
    for name in set(TRAIN_UNITS):
        path=base/f'refresh-700t-{name}.m3dmodel';units[name]=load_native(path);hashes[name]=hashlib.sha256(path.read_bytes()).hexdigest()
    shared={name:load_native(a.out/'shared'/f'{name}.m3dmodel') for name in ('office','fence','gate','guardHouse')}
    shared_far={name:load_native(a.out/'shared'/f'{name}-far.m3dmodel') for name in ('office','fence','gate','guardHouse')}
    out=a.out; (out/'models').mkdir(parents=True,exist_ok=True)
    records=[]
    for far in (False,True):
        for night in (False,True):
            id=f'liujia-{"far" if far else "near"}-{ "night" if night else "day"}'
            mesh=scene(osm,units,shared_far if far else shared,far,night)
            if night:
                mesh.triangles=[(flag,[(p,col if flag else ((int((col&255)*0.53)) | (int(((col>>8)&255)*0.57)<<8) | (int(((col>>16)&255)*0.64)<<16))) for p,col in points]) for flag,points in mesh.triangles]
            path=out/'models'/f'{id}.m3dmodel'
            write_native(path,mesh,{'osm':'© OpenStreetMap contributors, ODbL 1.0','train_unit_sha256':hashes,'inferred':['inspection hall','washing portal','office','substation','heights']})
            records.append({'id':id,'native':f'models/{id}.m3dmodel','triangles':len(mesh.triangles),'far':far,'night':night})
    manifest={'schema_version':1,'source':'OSM ODbL / game-native 700T / study estimates','directions':['top','bottom','left','right','front','back','isometric'],'models':records}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Exported',[(r['id'],r['triangles']) for r in records])

if __name__=='__main__':main()
