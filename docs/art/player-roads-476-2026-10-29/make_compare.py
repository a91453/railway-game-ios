import math
C=40.0  # points per cell
S=2     # pixel scale
def mid(r,c): return ((c+.5)*C,(r+.5)*C)
# a drag: diagonal-first then straight, like RoadDraft.extend
def extend(cells,to):
    at=cells[-1]
    while at!=to:
        nxt=(at[0]+(to[0]>at[0])-(to[0]<at[0]), at[1]+(to[1]>at[1])-(to[1]<at[1]))
        cells.append(nxt); at=nxt
cells=[(6,1)]
for p in [(6,5),(9,8),(9,13),(4,13)]: extend(cells,p)
built=set(cells)|{(5,5),(4,5)}  # a short spur too
# old: every 8-neighbour pair
def old_pairs(s):
    out=[]
    for (r,c) in sorted(s):
        for dr,dc in [(0,1),(1,-1),(1,0),(1,1)]:
            n=(r+dr,c+dc)
            if n in s: out.append(((r,c),n))
    return out
# new: port of RoadCentreLines
def new_lines(s):
    j={}
    for (r,c) in sorted(s):
        for dr,dc in [(0,1),(1,-1),(1,0),(1,1)]:
            n=(r+dr,c+dc)
            if n not in s: continue
            if dr and dc and ((r+dr,c) in s or (r,c+dc) in s): continue
            j.setdefault((r,c),[]).append(n); j.setdefault(n,[]).append((r,c))
    walked=set(); chains=[]
    def key(a,b): return (min(a,b),max(a,b))
    def walk(a,b):
        if key(a,b) in walked: return
        walked.add(key(a,b)); ch=[a,b]; prev,at=a,b
        while len(j.get(at,[]))==2:
            nx=j[at][1] if j[at][0]==prev else j[at][0]
            if key(at,nx) in walked: break
            walked.add(key(at,nx)); ch.append(nx); prev,at=at,nx
        chains.append(ch)
    for c in sorted(j):
        if len(j[c])!=2:
            for n in j[c]: walk(c,n)
    for c in sorted(j):
        for n in j[c]: walk(c,n)
    return [rounded([mid(*x) for x in ch]) for ch in chains]
def rounded(p):
    if len(p)<3: return p
    out=[p[0]]
    for i in range(1,len(p)-1):
        a,b,c=p[i-1],p[i],p[i+1]
        ix,iy=b[0]-a[0],b[1]-a[1]; ox,oy=c[0]-b[0],c[1]-b[1]
        il=math.hypot(ix,iy); ol=math.hypot(ox,oy)
        if abs(ix*oy-iy*ox)<1e-9: out.append(b); continue
        cut=min(C/4,il/2,ol/2)
        s=(b[0]-ix/il*cut,b[1]-iy/il*cut); e=(b[0]+ox/ol*cut,b[1]+oy/ol*cut)
        for k in range(5):
            t=k/4;u=1-t
            out.append((u*u*s[0]+2*u*t*b[0]+t*t*e[0],u*u*s[1]+2*u*t*b[1]+t*t*e[1]))
    out.append(p[-1]); return out
W,H=15*C,11*C
lane=2.95; old_w=C*0.35
# context: base-map streets (minor) on a few lines
streets=[[(0,2.5*C),(W,2.5*C)],[(11.5*C,0),(11.5*C,H)],[(0,10.6*C),(W,10.6*C)],[(3.2*C,0),(3.2*C,H)]]
def pl(pts): return " ".join(f"{x:.1f},{y:.1f}" for x,y in pts)
def base():
    o=f'<rect width="{W}" height="{H}" fill="#ECEEF6"/>'
    for s in streets:
        o+=f'<polyline points="{pl(s)}" fill="none" stroke="#CDD1E4" stroke-width="{lane+1.5}" stroke-linecap="round"/>'
        o+=f'<polyline points="{pl(s)}" fill="none" stroke="#FFFFFF" stroke-width="{lane}" stroke-linecap="round"/>'
    return o
def before():
    o=base()
    for a,b in old_pairs(built):
        o+=f'<polyline points="{pl([mid(*a),mid(*b)])}" fill="none" stroke="#CDD1E4" stroke-width="{old_w+2}" stroke-linecap="round"/>'
    for a,b in old_pairs(built):
        o+=f'<polyline points="{pl([mid(*a),mid(*b)])}" fill="none" stroke="#FFFFFF" stroke-width="{old_w}" stroke-linecap="round"/>'
    for (r,c) in built:
        o+=f'<rect x="{c*C}" y="{r*C}" width="{C}" height="{C}" fill="none" stroke="#262C57" stroke-opacity=".45" stroke-width="1"/>'
    return o
def after():
    o=base()
    L=new_lines(built)
    for l in L: o+=f'<polyline points="{pl(l)}" fill="none" stroke="#CDD1E4" stroke-width="{lane+1.5}" stroke-linecap="round" stroke-linejoin="round"/>'
    for l in L: o+=f'<polyline points="{pl(l)}" fill="none" stroke="#FFFFFF" stroke-width="{lane}" stroke-linecap="round" stroke-linejoin="round"/>'
    for l in L: o+=f'<polyline points="{pl(l)}" fill="none" stroke="#262C57" stroke-opacity=".5" stroke-width="1" stroke-dasharray="3 3"/>'
    return o
def panel(x,title,body):
    return f'<g transform="translate({x},40)">{body}<rect width="{W}" height="{H}" fill="none" stroke="#262C57"/></g><text x="{x}" y="28" font-family="sans-serif" font-size="16" fill="#262C57">{title}</text>'
total_w=2*W+60
svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w*S}" height="{(H+60)*S}" viewBox="0 0 {total_w} {H+60}"><rect width="100%" height="100%" fill="white"/>'
svg+=panel(20,"改前：鋪好後（道路模式，約 z15.5）",before())
svg+=panel(40+W,"改後：同一段路，和底圖巷弄同寬",after())
svg+='</svg>'
open("compare.svg","w").write(svg)
