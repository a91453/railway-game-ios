#!/usr/bin/env python3
"""TRACKCOUNT-STUDY: the real tracks and platforms across each station of the
urban lines on sale, from OSM (ODbL). See tools/real-railways/README.md."""
import json, pickle, math, sys, collections
import os
RES=os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../RailwayGameApp/Resources/RealRailways/')
ways,plats,nodes=pickle.load(open(sys.argv[1],'rb'))
LINES=[('ntdlrt','V'),('ntdlrt','VB'),('ntalrt','K'),('trtc','R_XBT'),('trtc','G_XBT'),('sanying','LB'),('trtc','BR'),('tymc','A')]
KEYS={'ntdlrt:V':['淡海'],'ntdlrt:VB':['淡海'],'ntalrt:K':['安坑'],'trtc:R_XBT':['新北投','淡水信義'],'trtc:G_XBT':['小碧潭'],'sanying:LB':['三鶯'],'trtc:BR':['文湖'],'tymc:A':['機場捷運']}
ACTIVE={'subway','light_rail','rail','narrow_gauge','monorail'}
def proj(lo,la,lat0):
    return ((lo)*111320*math.cos(math.radians(lat0)), la*110574)
def seginter(p1,p2,q1,q2):
    d=(p2[0]-p1[0])*(q2[1]-q1[1])-(p2[1]-p1[1])*(q2[0]-q1[0])
    if d==0: return None
    t=((q1[0]-p1[0])*(q2[1]-q1[1])-(q1[1]-p1[1])*(q2[0]-q1[0]))/d
    u=((q1[0]-p1[0])*(p2[1]-p1[1])-(q1[1]-p1[1])*(p2[0]-p1[0]))/d
    if 0<=t<=1 and 0<=u<=1: return t
    return None
def desc(t):
    k=t.get('railway') or 'platform'
    s=t.get('service','')
    return k+('/'+s if s else '')
only=sys.argv[2] if len(sys.argv)>2 else None
for sysname,lid in LINES:
    if only and only!=f'{sysname}:{lid}': continue
    line=[l for l in json.load(open(RES+sysname+'.json'))['lines'] if l['id']==lid][0]
    st=line['stations']; lat0=st[0]['lat']
    P=lambda lo,la: proj(lo,la,lat0)
    W=[(w[0],w[1],[P(*p) for p in w[2]],w[3]) for w in ways]
    PL=[(w[0],w[1],[P(*p) for p in w[2]]) for w in plats]
    print(f'== {sysname}:{lid} {line["name"]}')
    pts=[P(s['lon'],s['lat']) for s in st]
    STN=[(t.get('name',''),P(lo,la)) for _,r,t,lo,la in nodes if r in ('station','halt')]
    for i,s in enumerate(st):
        key=s['name'].removesuffix('站')
        c=[(math.hypot(q[0]-pts[i][0],q[1]-pts[i][1]),q) for nm,q in STN if key and key in nm]
        c=[x for x in c if x[0]<600]
        if c: pts[i]=min(c)[1]
    for i,s in enumerate(st):
        x,y=pts[i]
        a=pts[max(0,i-1)]; b=pts[min(len(pts)-1,i+1)]
        dx,dy=b[0]-a[0],b[1]-a[1]; L=math.hypot(dx,dy); dx/=L; dy/=L
        nx,ny=-dy,dx
        best=None
        for off in range(-200,201,10):
            cx,cy=x+dx*off,y+dy*off
            q1=(cx-nx*60,cy-ny*60); q2=(cx+nx*60,cy+ny*60)
            hits=[]
            for wid,t,ps,_ in W:
                if t.get('railway') not in ACTIVE or t.get('service')=='yard': continue
                nm=t.get('name','')
                if nm and not any(k in nm for k in KEYS[f'{sysname}:{lid}']): continue
                for p1,p2 in zip(ps,ps[1:]):
                    u=seginter(q1,q2,p1,p2)
                    if u is not None: hits.append((round(u*120-60),'T',desc(t),t.get('name',''),wid)); break
            for wid,t,ps in PL:
                for p1,p2 in zip(ps,ps[1:]):
                    u=seginter(q1,q2,p1,p2)
                    if u is not None: hits.append((round(u*120-60),'P','',t.get('name',t.get('ref','')),wid)); break
            # platform areas give two crossings: dedupe by id
            seen=set(); h2=[]
            for h in sorted(hits):
                if h[4] in seen: continue
                seen.add(h[4]); h2.append(h)
            nt=sum(1 for h in h2 if h[1]=='T')
            npf=sum(1 for h in h2 if h[1]=='P')
            key=(nt,npf,-abs(off))
            if abs(off)<=150 and (best is None or key>best[0]): best=(key,off,h2)
        (nt,npf,_),off,h2=best
        pattern=''.join('|' if h[1]=='T' else 'P' for h in h2)
        print(f'  {s["name"]}: tracks={nt} platforms={npf} at {off:+}m  {pattern}  ' + '; '.join(f'{h[0]}{h[1]}:{h[2]}:{h[3]}' for h in h2))
    # service tracks and switches near the line, assigned to nearest station
    svc=collections.defaultdict(list); sw=collections.Counter()
    kind=collections.Counter(t.get('railway') for _,t,_,_ in W if any(k in t.get('name','') for k in KEYS[f'{sysname}:{lid}'])).most_common(1)[0][0]
    for wid,t,ps,_ in W:
        if t.get('railway')!=kind or not t.get('service'): continue
        mx=sum(p[0] for p in ps)/len(ps); my=sum(p[1] for p in ps)/len(ps)
        d,j=min((math.hypot(mx-px,my-py),j) for j,(px,py) in enumerate(pts))
        if d<700:
            L=sum(math.hypot(b[0]-a[0],b[1]-a[1]) for a,b in zip(ps,ps[1:]))
            nm=t.get('name','')
            if nm and not any(k in nm for k in KEYS[f'{sysname}:{lid}']): continue
            svc[j].append('yard' if t['service']=='yard' else f'{t["service"]}({round(L)}m)')
    for nid,r,t,lo,la in nodes:
        if r!='switch': continue
        X,Y=P(lo,la)
        d,j=min((math.hypot(X-px,Y-py),j) for j,(px,py) in enumerate(pts))
        if d<700: sw[j]+=1
    for j,s in enumerate(st):
        if svc[j] or sw[j]: c=collections.Counter(x for x in svc[j] if x=='yard'); print(f'  near {s["name"]}: switches={sw[j]} yard-ways={c["yard"]} service: {", ".join(x for x in svc[j] if x!="yard")}')
