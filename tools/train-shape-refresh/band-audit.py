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
 shoulder=max(v[2] for v in band if 5.7<v[0]<9.2)
 lip=max(v[2] for v in band if v[0]>11.8)
 forward=max(v[0] for v in vertices)
 return {'shoulder_top_m':shoulder,'lip_top_m':lip,'forward_m':forward,'checks':[shoulder>2.2,lip>1.25,forward<12.6]}
old,new=inspect(prior),inspect(root)
assert all(new['checks']),new
assert not all(old['checks']),old
(root/'band-verification.json').write_text(json.dumps({'status':'VERIFIED','prior_actual_delivery':old,'final_actual_delivery':new,'checks':['raised coloured shoulder','band over low front lip','no unrequested extension'],'limits':'display geometry criteria; not engineering measurements or photographic similarity score'},indent=2)+'\n')
print('VERIFIED band coverage; prior actual delivery rejected',old,new)
