"""Check coloured shoulder/lip coverage on actual native triangles and reject old delivery."""
from pathlib import Path
import sys,struct,json
root,prior=map(Path,sys.argv[1:3])
def inspect(folder):
 b=(folder/'models/refresh-700t-cab.m3dmodel').read_bytes()
 n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 vertices=[struct.unpack_from('<fffI',b,start+i*52+4+j*16) for i in range(n) for j in range(3)]
 # Palette shopAwnings[0], little-endian RGB in the native file.
 band=[v for v in vertices if v[3]&0xffffff==0x8c8c3e]
 stations=[0,3.7,4.2,4.8,5.8,6.3,6.7,7.1,7.5,7.9,8.3,8.7,9.1,9.5,9.7,10,10.5,11,11.5,11.9]
 heights=[max(v[2] for v in band if abs(v[0]-x)<0.0001) for x in stations]
 slopes=[(h1-h0)/(x1-x0) for x0,x1,h0,h1 in zip(stations,stations[1:],heights,heights[1:])]
 jump=abs(heights[1]-heights[0]);peak=max(heights);slope=max(map(abs,slopes));bend=max(abs(a-b) for a,b in zip(slopes,slopes[1:]))
 return {'stations_x_m':stations,'upper_edge_height_m':heights,'body_join_step_m':jump,'peak_m':peak,'max_abs_slope':slope,'max_adjacent_slope_change':bend,'checks':[jump<0.015,1.9<peak<2.05,slope<0.22,bend<0.12]}
old,new=inspect(prior),inspect(root)
assert all(new['checks']),new
assert not all(old['checks']),old
(root/'band-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_actual_delivery':old,'final_actual_delivery':new,'checks':['continuous body join','low broad shoulder','bounded edge slope','no sharp wave/kink'],'limits':'display geometry criteria; not engineering measurements or photographic similarity score'},indent=2)+'\n')
print('VERIFIED band coverage; prior actual delivery rejected',old,new)
