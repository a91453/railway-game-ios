import measure as M, math, numpy as np, opt2
from opt2 import rc, raw, gg_factory
def make(radius,sigma,clamp):
    memo={}
    def corner(i,j):
        if (i,j) in memo: return memo[(i,j)]
        s=0;w=0
        for di in range(-radius,radius+1):
            for dj in range(-radius,radius+1):
                ww=math.exp(-(di*di+dj*dj)/(2*sigma*sigma)); s+=ww*rc(i+di,j+dj); w+=ww
        v=rc(i,j); d=max(-clamp,min(clamp,s/w-v)); memo[(i,j)]=v+d; return v+d
    return corner
for name,box in [('台北市中心',(25.030,121.500,25.060,121.560)),('林口坡地',(25.050,121.340,25.080,121.380))]:
    for radius,sigma,clamp in [(3,2.0,3.0)]:
        raw.clear(); M.LAT0=box[0]
        M.game_ground=gg_factory(make(radius,sigma,clamp))
        print(f'-- 半徑{radius} σ{sigma} 限±{clamp}m',end=' '); M.measure(name,box)
