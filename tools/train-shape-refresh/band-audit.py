"""Inspect the actual native shoulder, inset central nose and continuous body join."""
from pathlib import Path
import sys,struct,json
root,prior=map(Path,sys.argv[1:3])
def inspect(folder):
 b=(folder/'models/refresh-700t-cab.m3dmodel').read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 vertices=[struct.unpack_from('<fffI',b,start+i*52+4+j*16) for i in range(n) for j in range(3)]
 width=lambda v:max(p[1] for p in v)-min(p[1] for p in v)
 manifest=json.loads((folder/'manifest.json').read_text());body=manifest.get('livery',{}).get('high_speed',{}).get('body_argb',0xffeaf0f2)&0xffffff
 section=[v for v in vertices if abs(v[0]-10.5)<0.0001]
 white=[v for v in section if v[3]&0xffffff==body]
 front=[v for v in vertices if abs(v[0]-11.9)<0.0001 and v[3]&0xffffff==body]
 band=[v for v in vertices if v[3]&0xffffff==0x8c8c3e]
 stations=[0,3.7,4.2,4.8,5.8,6.3,6.7,7.1,7.5,7.9,8.3,8.7,9.1,9.5,9.7,10,10.5,11,11.5,11.9]
 heights=[max(v[2] for v in band if abs(v[0]-x)<0.0001) for x in stations]
 slopes=[(h1-h0)/(x1-x0) for x0,x1,h0,h1 in zip(stations,stations[1:],heights,heights[1:])]
 ratio=width(white)/width(section);front_width=width(front);join=abs(heights[1]-heights[0])
 return {'shoulder_section_x_m':10.5,'shoulder_width_m':width(section),'central_width_to_shoulder_ratio':ratio,'central_width_at_x11_9_m':front_width,'body_join_step_m':join,'stations_x_m':stations,'band_upper_edge_m':heights,'maximum_band_slope':max(map(abs,slopes)),'maximum_adjacent_slope_change':max(abs(a-b) for a,b in zip(slopes,slopes[1:])),'checks':[width(section)>3.2,ratio<0.85,front_width<1.2,join<0.015,max(heights)<2.3,max(abs(a-b) for a,b in zip(slopes,slopes[1:]))<0.15]}
old,new=inspect(prior),inspect(root)
assert all(new['checks']),new
assert all(old['checks']),old # Paint revision must preserve the preceding valid shoulder.
(root/'band-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_actual_delivery':old,'final_actual_delivery':new,'checks':['wide lower shoulder','central nose inset within shoulder','tapered central tip','continuous body paint join','restrained shoulder height','no sharp paint-edge kink'],'limits':'display geometry criteria; not engineering dimensions, owner approval or similarity score'},indent=2)+'\n')
print('VERIFIED shoulder/inset; both previous and final shoulder geometry retained',old,new)
