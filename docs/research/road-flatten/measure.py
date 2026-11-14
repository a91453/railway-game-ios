import struct, gzip, math, sys, json
import numpy as np
import mapbox_vector_tile as mvt
import os
REPO=os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../../RailwayGameApp/Resources')
# --- heights: read only needed rows
data=open(REPO+'/RealWorld/taiwan_heights.dat','rb').read()
north,west,cell=struct.unpack_from('<ddd',data,8); rows,cols=struct.unpack_from('<II',data,32)
offs=struct.unpack_from(f'<{rows+1}I',data,40); start=40+4*(rows+1)
cache={}
def row(r):
    if r in cache: return cache[r]
    body=data[start+offs[r]:start+offs[r+1]]; out=[];h=0;i=0;n=len(body)
    def vi():
        nonlocal i
        v=s=0
        while True:
            b=body[i];i+=1;v|=(b&0x7f)<<s
            if b<0x80: return v
            s+=7
    while i<n:
        v=vi()
        if v==0: out.extend([h]*vi())
        else: h+=(v>>1)^-(v&1); out.append(h)
    a=np.array(out,np.float64); cache[r]=a; return a
def H(lat,lon):
    r=(north-lat)/cell-0.5; c=(lon-west)/cell-0.5
    r0=int(math.floor(r)); c0=int(math.floor(c)); fr=r-r0; fc=c-c0
    g=lambda rr,cc: row(rr)[cc]
    return (g(r0,c0)*(1-fr)*(1-fc)+g(r0,c0+1)*(1-fr)*fc+g(r0+1,c0)*fr*(1-fc)+g(r0+1,c0+1)*fr*fc)
# game ground: whole-metre corners on a 64 m grid, triangulated; approximate local metric grid
LAT0=None
def game_ground(lat,lon):
    # local metres
    mx=(lon-121)*111320*math.cos(math.radians(LAT0)); mz=(lat-LAT0)*110574
    cx=math.floor(mx/64); cz=math.floor(mz/64); fx=mx/64-cx; fz=mz/64-cz
    def corner(i,j):
        la=LAT0+(j*64)/110574; lo=121+(i*64)/(111320*math.cos(math.radians(LAT0)))
        return round(H(la,lo))
    a=corner(cx,cz); b=corner(cx,cz+1); c=corner(cx+1,cz+1); d=corner(cx+1,cz)
    return a+fx*(c-b)+fz*(b-a) if fz>=fx else a+fx*(d-a)+fz*(c-d)
# --- pmtiles reader
pm=open(REPO+'/BaseMap/taiwan.pmtiles','rb').read()
def u64(o): return struct.unpack_from('<Q',pm,o)[0]
rootOff,rootLen,metaOff,metaLen,leafOff,leafLen,tdataOff=u64(8),u64(16),u64(24),u64(32),u64(40),u64(48),u64(56)
comp=pm[97]
def dec(b): return gzip.decompress(b) if b[:2]==b'\x1f\x8b' else b
def readdir(off,ln):
    b=dec(pm[off:off+ln]); i=0
    def vi():
        nonlocal i
        v=s=0
        while True:
            x=b[i];i+=1;v|=(x&0x7f)<<s
            if x<0x80:return v
            s+=7
    n=vi(); ids=[];last=0
    for _ in range(n): last+=vi(); ids.append(last)
    rl=[vi() for _ in range(n)]; ln_=[vi() for _ in range(n)]; of=[]
    for k in range(n):
        v=vi(); of.append(of[-1]+ln_[k-1] if v==0 and k>0 else v-1)
    return list(zip(ids,rl,ln_,of))
def tile_id(z,x,y):
    acc=((1<<(2*z))-1)//3; d=0; s=(1<<z)>>1
    while s>0:
        rx=1 if (x&s)>0 else 0; ry=1 if (y&s)>0 else 0
        d+=s*s*((3*rx)^ry)
        if ry==0:
            if rx==1: x=s-1-x; y=s-1-y
            x,y=y,x
        s>>=1
    return acc+d
def find(tid):
    off,ln=rootOff,rootLen
    for _ in range(4):
        ents=readdir(off,ln); lo,hi=0,len(ents)-1; hit=None
        while lo<=hi:
            m=(lo+hi)//2
            if ents[m][0]<=tid: hit=ents[m]; lo=m+1
            else: hi=m-1
        if not hit: return None
        i,rl,l,o=hit
        if rl==0: off,ln=leafOff+o,l; continue
        if tid<i+rl: return dec(pm[tdataOff+o:tdataOff+o+l])
        return None
def lonlat(z,x,y,px,py,ext):
    n=2**z; lon=(x+px/ext)/n*360-180
    yy=y+1-py/ext  # mvt y up in decoder default
    lat=math.degrees(math.atan(math.sinh(math.pi*(1-2*yy/n)))); return lat,lon
def roads(lat0,lon0,lat1,lon1):
    z=14; n=2**z
    def tx(lon): return int((lon+180)/360*n)
    def ty(lat): return int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n)
    out=[]
    for x in range(tx(lon0),tx(lon1)+1):
        for y in range(ty(lat1),ty(lat0)+1):
            b=find(tile_id(z,x,y))
            if not b: continue
            t=mvt.decode(b)
            if 'transportation' not in t: continue
            L=t['transportation']; ext=L['extent']
            for f in L['features']:
                p=f['properties']
                if p.get('brunnel') in ('bridge','tunnel') or p.get('ramp'): continue
                g=f['geometry']; lines=[g['coordinates']] if g['type']=='LineString' else (g['coordinates'] if g['type']=='MultiLineString' else [])
                for ln in lines:
                    out.append((p.get('class'),[lonlat(z,x,y,a,b2,ext) for a,b2 in ln]))
    return out
def resample(pts,step=8):
    xs=[];
    lat0=pts[0][0]; k=math.cos(math.radians(lat0))
    P=[((lo-pts[0][1])*111320*k,(la-lat0)*110574) for la,lo in pts]
    d=[0]
    for i in range(1,len(P)): d.append(d[-1]+math.dist(P[i-1],P[i]))
    if d[-1]<200: return None
    s=np.arange(0,d[-1],step); res=[]
    for v in s:
        i=max(1,np.searchsorted(d,v)); i=min(i,len(d)-1); t=(v-d[i-1])/max(1e-9,d[i]-d[i-1])
        la=pts[i-1][0]+(pts[i][0]-pts[i-1][0])*t; lo=pts[i-1][1]+(pts[i][1]-pts[i-1][1])*t
        dx=P[i][0]-P[i-1][0]; dz=P[i][1]-P[i-1][1]; L=math.hypot(dx,dz) or 1
        res.append((la,lo,dx/L,dz/L))
    return res
WIDTH={'motorway':24,'trunk':20,'primary':18,'secondary':14,'tertiary':10,'minor':7,'service':5}
def smooth(g,step,win,grade):
    w=int(win/step); n=len(g); c=np.cumsum(np.r_[0,g])
    t=np.array([(c[min(n,i+w+1)]-c[max(0,i-w)])/(min(n,i+w+1)-max(0,i-w)) for i in range(n)])
    # grade limit both passes
    for i in range(1,n): t[i]=min(max(t[i],t[i-1]-grade*step),t[i-1]+grade*step)
    for i in range(n-2,-1,-1): t[i]=min(max(t[i],t[i+1]-grade*step),t[i+1]+grade*step)
    return t
def measure(name,box):
    global LAT0; LAT0=box[0]
    stats={}
    for cls,pts in roads(*box):
        r=resample(pts)
        if not r: continue
        g=np.array([game_ground(la,lo) for la,lo,_,_ in r])
        hw=WIDTH.get(cls,8)/2; k=math.cos(math.radians(LAT0))
        cross=np.array([abs(game_ground(la+ (-ax*hw)/110574*-1, lo+(az*hw)/(111320*k)) - game_ground(la-(-ax*hw)/110574*-1, lo-(az*hw)/(111320*k))) for la,lo,ax,az in r])
        grade=np.abs(np.diff(g))/8
        s=smooth(g,8,80,0.06)
        dev=np.abs(s-g)
        # reversals of slope per km (ignore flat)
        sl=np.sign(np.round(np.diff(g[::8]),1)); sl=sl[sl!=0]; rev=int(np.sum(sl[1:]!=sl[:-1]))
        st=stats.setdefault(cls,dict(km=0,rev=0,grade=[],cross=[],dev=[],relief=[]))
        st['km']+=len(g)*8/1000; st['rev']+=rev; st['grade']+=list(grade); st['cross']+=list(cross); st['dev']+=list(dev)
    print('==',name)
    for cls in ['motorway','trunk','primary','secondary','tertiary','minor']:
        if cls not in stats: continue
        st=stats[cls]; q=lambda a,p: np.percentile(a,p)
        print(f"{cls:9s} {st['km']:6.1f} km  起伏反轉 {st['rev']/st['km']:5.1f}/km  縱坡 p95 {q(st['grade'],95)*100:4.1f}% max {max(st['grade'])*100:4.1f}%  橫向高差 p50 {q(st['cross'],50):.2f} p95 {q(st['cross'],95):.2f} m  平滑後離地 p50 {q(st['dev'],50):.2f} p95 {q(st['dev'],95):.2f} max {max(st['dev']):.2f} m")
if __name__=="__main__":
 for name,box in [('台北市中心',(25.030,121.500,25.060,121.560)),('高雄市區',(22.615,120.285,22.640,120.320)),('台中市區',(24.135,120.645,24.160,120.680)),('林口台地與龜山(坡地)',(25.050,121.340,25.080,121.380))]:
    measure(name,box)
