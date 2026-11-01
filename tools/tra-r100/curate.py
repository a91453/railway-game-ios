"""Select 20 transparent sheets for the ENTIRE R100/coach/assembly round.
Every source image is rendered from native vertices at the documented camera.
No reference photographs are copied into the delivery.
python3 tools/tra-r100/curate.py RUN PUBLIC_OVERVIEW
"""
from pathlib import Path
from PIL import Image, ImageDraw
import json
import sys

root=Path(sys.argv[1]); selected=root/'selected';selected.mkdir(exist_ok=True)
manifest=json.loads((root/'manifest.json').read_text())
loc=[m['id'] for m in manifest['models'] if m['id'].startswith('tra-r100-') and m.get('native_kind')!='assembly']
coach=[m['id'] for m in manifest['models'] if m['id'].startswith('tra-breezy-blue-coach-')]
formation=[m['id'] for m in manifest['models'] if m.get('native_kind')=='assembly']
views=['front','back','left','right','top','bottom','isometric']
def sheet(rows,path,title,width=1100,row_height=220):
    out=Image.new('RGBA',(width,48+row_height*len(rows)))
    d=ImageDraw.Draw(out);d.text((12,12),title,fill='#262c57')
    for i,(label,model,view,mode) in enumerate(rows):
        im=Image.open(root/'review'/mode/f'{model}-{view}.png');im.load()
        # Fixed rendering canvas/scale within each comparison group; never crop
        # or auto-fit the nontransparent model separately.
        scale=min((width-24)/im.width,(row_height-26)/im.height)
        im=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.LANCZOS)
        y=48+i*row_height
        out.alpha_composite(im,((width-im.width)//2,y+23))
        d.text((12,y+3),label,fill='#262c57')
    out.save(path,optimize=True)
def rows(ids,view,mode='color'):
    return [(id+' | '+view,id,view,mode) for id in ids]
for view in views:
    sheet(rows(loc,view),selected/f'locomotives-{view}.png','R100 orange / Breezy Blue | near / far | common metre camera')
    if coach:sheet(rows(coach,view),selected/f'coaches-{view}.png','Breezy Blue documented roles | near / far | common metre camera',row_height=160)
sheet(rows(loc,'isometric','clay')+rows(loc,'front','clay'),selected/'locomotives-clay.png','R100 geometry | common camera',row_height=180)
sheet(rows(coach,'isometric','clay') if coach else rows(loc,'left','clay'),selected/'coaches-clay.png','Documented coach geometry | role differences',row_height=170)
sheet(rows(loc,'left','silhouette')+rows(coach,'left','silhouette'),selected/'silhouettes.png','Near / far silhouettes | same camera within each vehicle class',row_height=120)
sheet(rows(loc,'left'),selected/'game-scale.png','R100 near / far | fixed metres | reduced game-view scale',width=600,row_height=135)
sheet(rows(formation,'left')+rows(formation,'isometric') if formation else rows(coach,'top'),selected/'formation.png','Assembly evidence and limitations: see README / formation.json',row_height=220)
sheet(rows(loc,'bottom')+rows(coach,'bottom'),selected/'running-gear.png','Native underbody / wheels | dimensions and unknowns in configuration',row_height=135)
overview=rows(loc[::2],'isometric')+rows(loc[::2],'left')+rows(coach[::2],'isometric')+rows(formation[:1],'left')
sheet(overview,Path(sys.argv[2]),'R100 and Breezy Blue | dated liveries / documented roles | appearance UNVERIFIED',width=1100,row_height=180)
pngs=list(selected.glob('*.png'))
assert len(pngs)<=20, len(pngs)
for p in pngs+[Path(sys.argv[2])]:
    assert p.stat().st_size<=2*1024*1024,(p,p.stat().st_size)
print(f'{len(pngs)} private PNG sheets + 1 public overview')
