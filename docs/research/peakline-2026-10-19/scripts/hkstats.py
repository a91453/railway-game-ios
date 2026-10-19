import json,sys,os,glob,statistics,struct
rows=[]
for g in glob.glob(sys.argv[1]+'/*/*/*.gltf'):
    j=json.load(open(g)); cat=g.split('/')[-3]
    tri=sum(j['accessors'][p['indices']]['count']//3 for m in j['meshes'] for p in m['primitives'])
    vert=sum(j['accessors'][p['attributes']['POSITION']]['count'] for m in j['meshes'] for p in m['primitives'])
    mn=[min(j['accessors'][p['attributes']['POSITION']]['min'][i] for m in j['meshes'] for p in m['primitives']) for i in range(3)]
    mx=[max(j['accessors'][p['attributes']['POSITION']]['max'][i] for m in j['meshes'] for p in m['primitives']) for i in range(3)]
    size=os.path.getsize(g)+sum(os.path.getsize(os.path.join(os.path.dirname(g),b['uri'])) for b in j['buffers'] if 'uri' in b)
    attrs=sorted({k for m in j['meshes'] for p in m['primitives'] for k in p['attributes']})
    rows.append(dict(cat=cat,name=os.path.basename(g)[:-5],tri=tri,vert=vert,size=size,ext=j.get('extensionsUsed',[]),req=j.get('extensionsRequired',[]),
        images=len(j.get('images',[])),materials=len(j.get('materials',[])),attrs=attrs,dims=[round(mx[i]-mn[i],1) for i in range(3)],gen=j['asset'].get('generator')))
json.dump(rows,open(sys.argv[2],'w'))
for cat in sorted({r['cat'] for r in rows}):
    rs=[r for r in rows if r['cat']==cat]; t=[r['tri'] for r in rs]
    print(cat,len(rs),'tri sum',sum(t),'median',statistics.median(t),'max',max(t),'>15000:',sum(x>15000 for x in t),'bytes',sum(r['size'] for r in rs),
          'ext',{tuple(r['ext']) for r in rs},'attrs',{tuple(r['attrs']) for r in rs},'images',sum(r['images'] for r in rs), 'gen',{r['gen'] for r in rs})
b=sorted([r for r in rows if r['cat']=='BUILDING'],key=lambda r:r['tri'])
for r in [b[0],b[len(b)//4],b[len(b)//2],b[3*len(b)//4],b[-1]]: print(r['name'],r['tri'],r['vert'],r['size'],r['dims'])
