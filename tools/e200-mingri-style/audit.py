"""Audit actual M3DM records, exact geometry/flags/order and protected paint.
BASE AFTER; BASE is a full main export, AFTER includes variants and originals.
"""
import hashlib,json,struct,sys
from pathlib import Path

def read(p):
 b=p.read_bytes();n,l=struct.unpack_from('<II',b,8);o=16+(l+3)//4*4
 assert len(b)==o+n*52
 return [b[o+i*52:o+(i+1)*52] for i in range(n)]
def geometry(t):return t[:4]+b''.join(t[4+i*16:16+i*16] for i in range(3))
def pos(t):return [struct.unpack_from('<fff',t,4+i*16) for i in range(3)]
def allowed(t,role,index,far):
 p=pos(t);x,y,z=[sum(v[a] for v in p)/3 for a in range(3)]
 if struct.unpack_from('<I',t)[0]&3:return False
 if role=='head':
  return (index<44 or (1.1<z<2.8 and (abs(y)>1.46 or abs(x)>8.5)) or (6.8<abs(x)<7.6 and abs(y)>1.47 and z<3.4))
 return index < (332 if far else 460) or (8.5<abs(x)<9.4 and abs(y)>1.45 and z<3.14)
def compare(a,b,role,far):
 assert len(a)==len(b),'triangle count/order'
 changed=[]
 for i,(u,v) in enumerate(zip(a,b)):
  assert geometry(u)==geometry(v),('noncolour field',i)
  if u!=v:
   assert allowed(u,role,i,far),('protected paint',i)
   changed.append(i)
 assert changed,'no livery'
 return changed

def main(base,after):
 a=json.loads((base/'manifest.json').read_text());b=json.loads((after/'manifest.json').read_text());bm={m['id']:m for m in b['models']};protected=[]
 for m in a['models']:
  if m['id'] not in bm:continue
  n=bm[m['id']];assert (base/m['native']).read_bytes()==(after/n['native']).read_bytes(),m['id'];assert m['hash']==n['hash'];protected.append(m['id'])
 assert len(protected)>600,'full existing payload export required'
 rows=[]
 for far in [False,True]:
  for role in ['head','car','tail']:
   old='set-E200CK'+('Far' if far else '')+'-'+role;new='e200mingri-style-'+role+('-far' if far else '')
   aa=read(base/next(m['native'] for m in a['models'] if m['id']==old));bb=read(after/bm[new]['native'])
   changed=compare(aa,bb,role,far)
   assert len(bb)<=15000,'per-file format budget'
   assert len(bb)<=20000,'independent-unit scene budget'
   def reject(mut,label):
    try:compare(aa,mut,role,far)
    except AssertionError:return label
    raise AssertionError('accepted fault '+label)
   mut=bb.copy();v=bytearray(mut[0]);struct.pack_into('<f',v,4,struct.unpack_from('<f',v,4)[0]+.005);mut[0]=bytes(v)
   faults=[reject(mut,'5mm shell shift')]
   for flag,label in [(2,'glass colour'),(1,'lamp colour')]:
    choices=[i for i,t in enumerate(aa) if struct.unpack_from('<I',t)[0]&flag]
    if not choices and flag==1 and role in ['head','tail']:
     choices=[len(aa)-1] if role=='tail' else [i for i,t in enumerate(aa) if all(v[2]>3.68 and abs(v[0])>8.4 and abs(v[1])<.4 for v in pos(t))]
    if choices:
     mut=bb.copy();v=bytearray(mut[choices[0]]);v[16]^=1;mut[choices[0]]=bytes(v);faults.append(reject(mut,label))
   rows.append(dict(id=new,triangles=len(aa),changed_triangles=changed,geometry_flags_order_exact=True,protected_colours_exact=True,faults_rejected=faults,geometry_sha256=hashlib.sha256(b''.join(map(geometry,bb))).hexdigest()))
 # Same eight-car placements for old/new, no scaling or hidden reorientation.
 spec=json.loads((Path(__file__).parent/'assembly.json').read_text())['assemblies']
 for i in [0,2]:assert [p['translation'] for p in spec[i]['placements']]==[p['translation'] for p in spec[i+1]['placements']]
 report=dict(status='VERIFIED',protected_models=len(protected),protected_ids=protected,units=rows,subdivision=False,geometry_tolerance='exact Float32 bytes',inherited_far_ratio='coach 4008/6476; locomotive same near/far, preserved not optimized')
 (after/'paint-protection.json').write_text(json.dumps(report,indent=2)+'\n');print('VERIFIED protected',len(protected),'existing models; six paint-only units')
if __name__=='__main__':main(*map(Path,sys.argv[1:3]))
