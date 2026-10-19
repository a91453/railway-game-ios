"""Render .m3dmodel files (format v1) as flat-shaded orthographic views with PIL.
Painter's algorithm; alpha-0 (paint) colour replaced by a sample stripe colour.
Usage: python3 -I render_m3d.py out.png title1=file1 title2=file2 ..."""
import struct, sys, json, math
from PIL import Image, ImageDraw
def load(p):
    b=open(p,'rb').read(); assert b[:4]==b'M3DM'
    n,plen=struct.unpack('<II',b[8:16]); at=16+((plen+3)//4)*4
    src=json.loads(b[16:16+plen]); tris=[]
    for i in range(n):
        o=at+i*52; flag=struct.unpack('<I',b[o:o+4])[0]; pts=[];cols=[]
        for c in range(3):
            x,y,z,col=struct.unpack('<fffI',b[o+4+c*16:o+20+c*16]); pts.append((x,y,z)); cols.append(col)
        tris.append((flag,pts,cols[0]))
    return src,tris
STRIPE=(0x3E,0x8E,0x6E)
def color(c):
    r,g,b,a=c&255,(c>>8)&255,(c>>16)&255,c>>24
    return STRIPE if a==0 else (r,g,b)
def view(tris, yaw, pitch, size, scale):
    # camera direction v (from model towards eye): yaw about +z from +x, pitch above horizon
    v=(math.cos(pitch)*math.cos(yaw), math.cos(pitch)*math.sin(yaw), math.sin(pitch))
    f=tuple(-c for c in v)
    r=(f[1]*1-0, 0-f[0]*1, 0.0); ln=math.hypot(r[0],r[1]) or 1; r=(r[0]/ln,r[1]/ln,0.0)
    u=(r[1]*f[2]-r[2]*f[1], r[2]*f[0]-r[0]*f[2], r[0]*f[1]-r[1]*f[0])
    L=(0.4,0.3,0.86); n=math.sqrt(sum(c*c for c in L)); L=[c/n for c in L]
    img=Image.new('RGB',size,(246,244,238)); d=ImageDraw.Draw(img); polys=[]
    dot=lambda a,b: a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
    for flag,pts,col in tris:
        q=[(dot(p,r),dot(p,u),dot(p,v)) for p in pts]
        a=[pts[1][i]-pts[0][i] for i in range(3)]; b=[pts[2][i]-pts[0][i] for i in range(3)]
        nrm=[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]; ln=math.sqrt(sum(c*c for c in nrm)) or 1
        lam=abs(sum(nrm[i]/ln*L[i] for i in range(3)))
        base=color(col); fct=0.55+0.45*lam
        c=tuple(min(255,int(x*fct)) for x in base)
        if flag&1: c=(255,226,150)
        polys.append((sum(p[2] for p in q)/3,[(size[0]/2+p[0]*scale,size[1]*0.92-p[1]*scale) for p in q],c))
    for _,p,c in sorted(polys,key=lambda t:t[0]): d.polygon(p,fill=c)
    return img
out=sys.argv[1]; items=[a.split('=',1) for a in sys.argv[2:]]
views=[('left side (+y)',math.pi/2,0),('front (+x)',0,0),('3/4 front-left',math.radians(40),math.radians(25)),('rear (-x)',math.pi,0)]
W,H=360,220; sheet=Image.new('RGB',(W*len(views),(H+24)*len(items)),(255,255,255)); dd=ImageDraw.Draw(sheet)
for r,(title,path) in enumerate(items):
    src,tris=load(path)
    for c,(vn,yaw,pitch) in enumerate(views):
        allp=[p for t in tris for p in t[1]]; ext=max(max(p[i] for p in allp)-min(p[i] for p in allp) for i in range(3)); img=view(tris,yaw,pitch,(W,H),min(24,0.8*H/ext)); sheet.paste(img,(c*W,r*(H+24)+24))
        dd.text((c*W+6,r*(H+24)+6),f'{title}: {vn}  {len(tris)} tris',fill=(0,0,0))
sheet.save(out); print(out)
