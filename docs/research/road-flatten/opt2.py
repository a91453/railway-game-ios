import measure as M, math, numpy as np
raw={}
def rc(i,j):
    k=(i,j)
    if k not in raw:
        la=M.LAT0+(j*64)/110574; lo=121+(i*64)/(111320*math.cos(math.radians(M.LAT0))); raw[k]=round(M.H(la,lo))
    return raw[k]
KER=None
def make(radius,relief):
    memo={}
    def corner(i,j):
        if (i,j) in memo: return memo[(i,j)]
        vals=[];ws=[]
        for di in range(-radius,radius+1):
            for dj in range(-radius,radius+1):
                w=math.exp(-(di*di+dj*dj)/(2*(radius/1.5)**2)); vals.append(rc(i+di,j+dj)); ws.append(w)
        v=rc(i,j)
        if max(vals)-min(vals)<=relief: v=sum(a*b for a,b in zip(vals,ws))/sum(ws)
        memo[(i,j)]=v; return v
    return corner
def gg_factory(corner):
    def gg(lat,lon):
        mx=(lon-121)*111320*math.cos(math.radians(M.LAT0)); mz=(lat-M.LAT0)*110574
        cx=math.floor(mx/64); cz=math.floor(mz/64); fx=mx/64-cx; fz=mz/64-cz
        a=corner(cx,cz); b=corner(cx,cz+1); c=corner(cx+1,cz+1); d=corner(cx+1,cz)
        return a+fx*(c-b)+fz*(b-a) if fz>=fx else a+fx*(d-a)+fz*(c-d)
    return gg
import sys
if __name__=="__main__":
  for name,box in [("台北市中心",(25.030,121.500,25.060,121.560)),('高雄市區',(22.615,120.285,22.640,120.320)),('林口坡地',(25.050,121.340,25.080,121.380))]:
    for radius,relief in [(1,6),(2,8)]:
        raw.clear(); M.LAT0=box[0]
        M.game_ground=gg_factory(make(radius,relief))
        print(f'-- 地面先平滑 半徑{radius}格 起伏≤{relief}m',end=' '); M.measure(name,box)
