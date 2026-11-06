#!/usr/bin/env python3
"""Make the public overview and a file:// usable private viewer."""
import argparse
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

p=argparse.ArgumentParser();p.add_argument('private',type=Path);p.add_argument('public',type=Path);a=p.parse_args()
root=a.private;pub=a.public;pub.mkdir(parents=True,exist_ok=True)
manifest=json.loads((root/'manifest.json').read_text())
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
head=ImageFont.truetype(font,36);small=ImageFont.truetype(font,23)
canvas=Image.new('RGB',(1600,1060),'#e8eee9');draw=ImageDraw.Draw(canvas)
draw.text((45,24),'THSR Liujia depot | exterior study',font=head,fill='#262C57')
for i,(id,label,bg) in enumerate((('liujia-near-day','Near / day','#e8eee9'),('liujia-far-day','Far / day','#e8eee9'),('liujia-near-night','Near / night','#263C40'),('liujia-far-night','Far / night','#263C40'))):
    x=35+(i%2)*785;y=100+(i//2)*475
    draw.rectangle((x,y,x+750,y+450),fill=bg)
    img=Image.open(root/'views'/id/'isometric.png').convert('RGBA')
    img.thumbnail((745,405))
    canvas.paste(img,(x+(750-img.width)//2,y+36+(405-img.height)//2),img)
    draw.text((x+15,y+10),label,font=small,fill='#FFFFFF' if 'night' in id else '#262C57')
draw.text((45,1030),'OSM geometry: © OpenStreetMap contributors (ODbL 1.0). Shed and facility roles are estimates.',font=ImageFont.truetype(font,17),fill='#262C57')
canvas.save(pub/'overview.png',optimize=True)

renderer=(root/'renderer.js').read_text().replace('export const ','const ').replace('export class ','class ')
html='''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>六家基地研究模型</title><style>
body{margin:0;background:#e8eee9;color:#262C57;font:16px system-ui}main{max-width:1100px;margin:auto;padding:16px}canvas{display:block;width:100%;height:auto;background:#dbe6de;border:1px solid #9daab0;touch-action:none}button,input,select{font:inherit;margin:4px;padding:6px}.row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}#status{min-height:1.5em}</style><main><h1>高鐵六家基地 · 研究組景</h1><p>本頁直接以 file:// 開啟。選擇 models/ 中任一 M3DM 檔，即可旋轉查看；同資料夾的 views/ 有日夜七方向 PNG。幾何依 OSM，檢修庫用途與高度為推估，並非營運配置。</p><div class="row"><input id="file" type="file" accept=".m3dmodel"><label>方向 <select id="direction"><option value="isometric">斜上</option><option value="top">上</option><option value="bottom">下</option><option value="left">左</option><option value="right">右</option><option value="front">前</option><option value="back">後</option></select></label><label>縮放 <input id="zoom" type="range" min="0.5" max="3" step="0.05" value="1"></label><label>背景 <select id="background"><option value="#dbe6de">日</option><option value="#263c40">夜</option></select></label></div><canvas id="canvas" width="1100" height="680"></canvas><p id="status" role="status">請選擇模型檔</p><p>拖曳可旋轉。<a href="SOURCE.md">SOURCE.md</a> · © OpenStreetMap contributors, ODbL 1.0</p></main><script>
'''+renderer+'''
const $=id=>document.getElementById(id);const r=new NativeRenderer($('canvas'));let direction='isometric',zoom=1,vector=null,az=0.785,el=0.5,loaded=false;
function draw(){if(!loaded)return;r.render(direction,{width:1100,height:680,zoom,vector});$('canvas').style.background=$('background').value}
$('file').onchange=async e=>{const f=e.target.files[0];if(!f)return;try{r.load(await f.arrayBuffer());loaded=true;vector=null;direction='isometric';$('status').textContent=f.name+' · '+r.count/3+' triangles';draw()}catch(err){$('status').textContent=String(err)}};
$('direction').onchange=e=>{direction=e.target.value;vector=null;draw()};$('zoom').oninput=e=>{zoom=+e.target.value;draw()};$('background').onchange=draw;
let last=null;$('canvas').onpointerdown=e=>{last=[e.clientX,e.clientY];e.target.setPointerCapture(e.pointerId)};$('canvas').onpointermove=e=>{if(!last)return;az+=(e.clientX-last[0])*0.008;el=Math.max(-1.45,Math.min(1.45,el+(e.clientY-last[1])*0.008));last=[e.clientX,e.clientY];vector=[Math.cos(el)*Math.cos(az),Math.cos(el)*Math.sin(az),Math.sin(el)];draw()};$('canvas').onpointerup=()=>last=null;
</script></html>'''
(root/'viewer.html').write_text(html)
print('Wrote overview and standalone viewer')
