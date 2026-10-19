#!/usr/bin/env python3
"""Offline research only: compare a WorldCover crop with the exact bundled map.
No game files are written. Inputs and attribution are documented in the report.
"""
import argparse, collections, gzip, hashlib, json, math, pathlib, time
import numpy as np
import rasterio
from rasterio.features import rasterize
from rasterio.windows import from_bounds
from pmtiles.reader import Reader, MmapSource
import mapbox_vector_tile
from shapely.geometry import shape, box, mapping
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm

ap=argparse.ArgumentParser();ap.add_argument('--repo',type=pathlib.Path,required=True);ap.add_argument('--tile',type=pathlib.Path,required=True);ap.add_argument('--out',type=pathlib.Path,required=True)
a=ap.parse_args();a.out.mkdir(parents=True,exist_ok=True);t=time.perf_counter()
bounds=(120.76,23.80,120.82,23.86);w,s,e,n=bounds
with rasterio.open(a.tile) as src:
    win=from_bounds(*bounds,src.transform).round_offsets().round_lengths()
    wc=src.read(1,window=win);tr=src.window_transform(win);profile=src.profile
    profile.update(width=wc.shape[1],height=wc.shape[0],transform=tr,compress='deflate',tiled=True)
    with rasterio.open(a.out/'worldcover-jiji.tif','w',**profile) as dst:dst.write(wc,1)
height,width=wc.shape
lon=tr.c+(np.arange(width)+.5)*tr.a;lat=tr.f+(np.arange(height)+.5)*tr.e
xx,yy=np.meshgrid(lon,lat)
resources=a.repo/'RailwayGameApp/Resources'
pm=resources/'BaseMap/taiwan.pmtiles';z=14;tiles=1<<z
xt=lambda lon:math.floor((lon/360+.5)*tiles)
yt=lambda lat:math.floor((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*tiles)
shapes=[];tile_count=0;feature_count=collections.Counter()
cover_code={'wood':10,'grass':30,'wetland':90,'sand':60}
with pm.open('rb') as f:
    reader=Reader(MmapSource(f))
    for tx in range(xt(w),xt(e)+1):
        for ty in range(yt(n),yt(s)+1):
            tile=reader.get(z,tx,ty)
            if not tile:continue
            tile_count+=1
            decoded=mapbox_vector_tile.decode(gzip.decompress(tile),default_options={'y_coord_down':True})
            for layer in ('landcover','park','water'):
                if layer not in decoded:continue
                extent=decoded[layer]['extent']
                def geo(coords):
                    if isinstance(coords[0],(int,float)):
                        u=(tx+coords[0]/extent)/tiles;v=(ty+coords[1]/extent)/tiles
                        return [360*(u-.5),math.degrees(math.atan(math.sinh(math.pi*(1-2*v))))]
                    return [geo(c) for c in coords]
                for feature in decoded[layer]['features']:
                    code=80 if layer=='water' else 70 if layer=='park' else cover_code.get(feature['properties'].get('class'),0)
                    if not code:continue
                    feature_count[layer+':'+str(feature['properties'].get('class'))]+=1
                    geom=feature['geometry']
                    tile_w=tx/tiles*360-180;tile_e=(tx+1)/tiles*360-180
                    tile_n=math.degrees(math.atan(math.sinh(math.pi*(1-2*ty/tiles))))
                    tile_s=math.degrees(math.atan(math.sinh(math.pi*(1-2*(ty+1)/tiles))))
                    clipped=shape({'type':geom['type'],'coordinates':geo(geom['coordinates'])}).intersection(box(tile_w,tile_s,tile_e,tile_n))
                    if not clipped.is_empty:shapes.append((mapping(clipped),code))
cover_order={30:0,60:1,90:2,10:3,70:4,80:5}
shapes.sort(key=lambda item:cover_order[item[1]])
base=rasterize(shapes,out_shape=wc.shape,transform=tr,dtype='uint8',fill=0)
# Match PlaceGrid's majority threshold and tie order; these are visual samples
# of the bundled geographic grids, not an imported GameWorld or save.
places=json.loads((resources/'RealWorld/taiwan_places.json').read_text());step=places['cellDegrees']/places['zones']['cuts']
rr=np.floor((places['north']-yy)/step).astype(int);cc=np.floor((xx-places['west'])/step).astype(int)
best=np.zeros(wc.shape,dtype=np.uint8);zone=np.zeros_like(best)
for name,code in [('industrial',100),('park',70),('farmland',40)]:
    for run in places['zones']['layers'][name]:
        row,col=run['r'],run['c']
        if row<rr.min() or row>rr.max() or col>cc.max() or col+len(run['p'])<cc.min():continue
        for k,points in enumerate(run['p']):
            if points<8:continue
            mask=(rr==row)&(cc==col+k)&(points>best);best[mask]=points;zone[mask]=code
base[zone!=0]=zone[zone!=0]
water_file=json.loads((resources/'RealWorld/taiwan_water.json').read_text());wr=np.floor((water_file['north']-yy)/water_file['cellDegrees']).astype(int);wc_col=np.floor((xx-water_file['west'])/water_file['cellDegrees']).astype(int)
water=np.zeros(wc.shape,dtype=bool)
for run in water_file['water']:
    if run[0]<wr.min() or run[0]>wr.max():continue
    col=run[1]
    for k in range(2,len(run),2):
        if k>2:col+=run[k-1]
        water|=(wr==run[0])&(wc_col>=col)&(wc_col<col+run[k]);col+=run[k]
base[water]=80
fallback=(base==0)&np.isin(wc,[10,20,30,90,95,100]);merged=base.copy();merged[fallback]=wc[fallback]
classes=[0,10,20,30,40,50,60,70,80,90,95,100]
labels=['unclassified','trees','shrubs','grass','crops','built-up','bare / OSM sand','park / WC snow','water','wetland','mangroves','industrial / WC moss']
# Shared colours only where semantics agree. Park and industry are labelled
# separately in the panel titles: they are not WorldCover classes.
colours=['#eeeae1','#387d45','#9fbc65','#c3d778','#dfbc64','#c16c6c','#bcb1a0','#55aa80','#619dc6','#63c1b1','#287b77','#777889']
cmap=ListedColormap(colours);norm=BoundaryNorm([-.5,5,15,25,35,45,55,65,75,85,92.5,97.5,105],cmap.N)
fig,axes=plt.subplots(1,3,figsize=(15,5),layout='constrained')
for ax,data,title in zip(axes,[base,wc,merged],['Bundled OSM + zones + water','WorldCover 2021 v200','Visual fallback only (candidate)']):
    ax.imshow(data,extent=bounds[0:1]+bounds[2:3]+bounds[1:2]+bounds[3:4],cmap=cmap,norm=norm,origin='upper',interpolation='nearest',aspect=1/math.cos(math.radians((s+n)/2)))
    ax.set_title(title);ax.set_xlabel('longitude');ax.set_ylabel('latitude')
from matplotlib.patches import Patch
fig.legend(handles=[Patch(color=c,label=l) for c,l in zip(colours[:10],labels[:10])],loc='outside lower center',ncol=5,fontsize=8)
fig.suptitle('Jiji, Taiwan: 120.76–120.82 E / 23.80–23.86 N\nPixel-centre comparison; not ground truth or an iPhone screenshot',fontsize=12)
fig.text(.5, -.075, '© OpenStreetMap contributors (ODbL); © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium. CC BY 4.0.', ha='center', fontsize=7)
fig.savefig(a.out/'worldcover-comparison.png',dpi=160,bbox_inches='tight');plt.close(fig)
# A categorical majority resample; never interpolate class IDs.
blocks=wc.reshape(120,6,120,6).transpose(0,2,1,3).reshape(120,120,36)
coarse=np.zeros((120,120),dtype=np.uint8)
for r in range(120):
    for c in range(120):coarse[r,c]=np.bincount(blocks[r,c],minlength=101).argmax()
(a.out/'worldcover-jiji-majority-120.dat').write_bytes(coarse.tobytes())
np.savez_compressed(a.out/'comparison-masks.npz',baseline=base,worldcover=wc,fallback=fallback,water=water,zone=zone)
pixel_km2=(111_320*tr.a*math.cos(math.radians((s+n)/2)))*(111_320*-tr.e)/1e6
count=lambda mask:int(np.count_nonzero(mask))
counts={str(code):count(wc==code) for code in classes if count(wc==code)}
cross={str(code):{str(v):count((wc==code)&(base==v)) for v in classes if count((wc==code)&(base==v))} for code in classes if count(wc==code)}
metrics=dict(bounds=bounds,shape=list(wc.shape),pixels=wc.size,approx_km2=wc.size*pixel_km2,classes=counts,baseline_cross=cross,baseline_unclassified_pixels=count(base==0),fallback_pixels=count(fallback),fallback_km2=count(fallback)*pixel_km2,wc_crops_outside_game_farms=count((wc==40)&(zone!=40)),wc_water_on_game_dry=count((wc==80)&~water),wc_nonwater_on_game_water=count((wc!=80)&water),candidate_changes_game_water=count(fallback&water),candidate_changes_zones=count(fallback&(zone!=0)),coarse_disagreement_pixels=count(wc!=np.repeat(np.repeat(coarse,6,axis=0),6,axis=1)),tiles=tile_count,features=dict(feature_count),seconds=time.perf_counter()-t,inputs={str(path.relative_to(a.repo)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [pm,resources/'RealWorld/taiwan_places.json',resources/'RealWorld/taiwan_water.json']})
(a.out/'worldcover-metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
print(json.dumps(metrics,indent=2))
