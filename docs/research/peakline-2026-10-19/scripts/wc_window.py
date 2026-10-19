"""Read an ESA WorldCover 2021 v200 window over HTTP (COG range reads) and save it as .npy + PNG.
Usage: venv/bin/python wc_window.py W S E N out_prefix"""
import sys, time, json, numpy as np, rasterio
from rasterio.windows import from_bounds
from PIL import Image
W,S,E,N=map(float,sys.argv[1:5]); out=sys.argv[5]
tile=f"N{int(S//3*3):02d}E{int(W//3*3):03d}"
url=f"https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{tile}_Map.tif"
t=time.time()
with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR', CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif'):
    with rasterio.open('/vsicurl/'+url) as src:
        win=from_bounds(W,S,E,N,src.transform); a=src.read(1,window=win)
        meta=dict(url=url,crs=str(src.crs),res=src.res,shape=a.shape,tile_size=src.width,blocks=src.block_shapes[0],overviews=src.overviews(1),dtype=str(a.dtype),seconds=round(time.time()-t,1))
np.save(out+'.npy',a)
COL={10:(0,100,0),20:(255,187,34),30:(255,255,76),40:(240,150,255),50:(250,0,0),60:(180,180,180),70:(240,240,240),80:(0,100,200),90:(0,150,160),95:(0,207,117),100:(250,230,160)}
rgb=np.zeros(a.shape+(3,),np.uint8)
for k,c in COL.items(): rgb[a==k]=c
Image.fromarray(rgb).save(out+'.png')
u,c=np.unique(a,return_counts=True); meta['classes']={int(k):round(int(v)/a.size*100,2) for k,v in zip(u,c)}
print(json.dumps(meta))
