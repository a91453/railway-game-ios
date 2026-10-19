"""List a remote zip's central directory and extract selected members with HTTP Range requests.
Usage: python3 -I zip_range.py URL list OUT.json | python3 -I zip_range.py URL get PREFIX OUTDIR"""
import sys, struct, json, zlib, urllib.request, os
url=sys.argv[1]
def rng(a,b):
    r=urllib.request.Request(url,headers={'Range':f'bytes={a}-{b}'}); return urllib.request.urlopen(r,timeout=120).read()
size=int(urllib.request.urlopen(urllib.request.Request(url,method='HEAD'),timeout=60).headers['Content-Length'])
tail=rng(size-70000,size-1)
i=tail.rfind(b'PK\x05\x06'); z64=tail.rfind(b'PK\x06\x06')
if z64>=0:
    cd_size,cd_off=struct.unpack('<QQ',tail[z64+40:z64+56])
else:
    cd_size,cd_off=struct.unpack('<II',tail[i+12:i+20])
cd=rng(cd_off,cd_off+cd_size-1); p=0; ents=[]
while p<len(cd) and cd[p:p+4]==b'PK\x01\x02':
    meth,=struct.unpack('<H',cd[p+10:p+12]); csz,usz=struct.unpack('<II',cd[p+20:p+28]); nl,el,cl=struct.unpack('<HHH',cd[p+28:p+34]); lho,=struct.unpack('<I',cd[p+42:p+46])
    name=cd[p+46:p+46+nl].decode('utf-8','replace'); extra=cd[p+46+nl:p+46+nl+el]
    q=0
    while q+4<=len(extra):
        hid,hl=struct.unpack('<HH',extra[q:q+4])
        if hid==1:
            vals=list(struct.unpack('<'+'Q'*(hl//8),extra[q+4:q+4+hl//8*8])); k=0
            if usz==0xFFFFFFFF: usz=vals[k];k+=1
            if csz==0xFFFFFFFF: csz=vals[k];k+=1
            if lho==0xFFFFFFFF: lho=vals[k];k+=1
        q+=4+hl
    ents.append(dict(name=name,method=meth,csize=csz,size=usz,offset=lho)); p+=46+nl+el+cl
if sys.argv[2]=='list':
    json.dump(dict(url=url.split('?')[0],bytes=size,entries=ents),open(sys.argv[3],'w')); print(len(ents),'entries', size,'bytes')
else:
    pre=sys.argv[3]; out=sys.argv[4]
    for e in ents:
        if not e['name'].startswith(pre) or e['name'].endswith('/'): continue
        h=rng(e['offset'],e['offset']+29); nl,el=struct.unpack('<HH',h[26:30])
        d=rng(e['offset']+30+nl+el,e['offset']+30+nl+el+e['csize']-1)
        data=zlib.decompress(d,-15) if e['method']==8 else d
        path=os.path.join(out,e['name']); os.makedirs(os.path.dirname(path),exist_ok=True); open(path,'wb').write(data); print(len(data),e['name'])
