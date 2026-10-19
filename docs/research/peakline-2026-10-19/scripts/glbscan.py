import json, struct, sys, os, collections
def head(p):
    b=open(p,'rb').read()
    if b[:4]!=b'glTF': return None
    n,t=struct.unpack('<I4s',b[12:20]); j=json.loads(b[20:20+n])
    return len(b), j
rows=[]; agg=collections.Counter()
for p in sys.argv[1:]:
    r=head(p)
    if not r: continue
    size,j=r
    req=tuple(sorted(j.get('extensionsRequired',[]))); used=tuple(sorted(j.get('extensionsUsed',[])))
    imgs=collections.Counter(i.get('mimeType','uri') for i in j.get('images',[]))
    agg[req]+=1
    rows.append((p,size,j.get('asset',{}).get('generator',''),req,used,dict(imgs),len(j.get('meshes',[])),len(j.get('nodes',[]))))
for r in rows: print(json.dumps(r,ensure_ascii=False))
print('AGG',{str(k):v for k,v in agg.items()})
