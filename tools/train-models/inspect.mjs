// Self-contained native WebGL inspector, embedded downloads, no ZIP.
// node inspect.mjs RUN OUT.html (use a curated run for a <=50 MB delivery).
import {readFileSync, writeFileSync, existsSync} from 'node:fs';
import {resolve, basename} from 'node:path';
const [rootArg, out] = process.argv.slice(2), root = resolve(rootArg);
const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json')));
const models = manifest.models.map(m => ({...m, files: ['native', 'glb'].filter(k => m[k]).map(kind => ({
  kind, name: basename(m[kind]), data: readFileSync(resolve(root, m[kind])).toString('base64')
}))}));
const status = existsSync(resolve(root, 'status.json')) ? JSON.parse(readFileSync(resolve(root, 'status.json'))) : JSON.parse(readFileSync(new URL('./status-template.json', import.meta.url)));
const scene = readFileSync(new URL('../emu900-native/scene.js', import.meta.url), 'utf8').replace('export function', 'function');
const renderer = readFileSync(new URL('./renderer.js', import.meta.url), 'utf8').replace(/^import .*;\n/, '').replaceAll('export ', '');
const encode = value => JSON.stringify(value).replaceAll('<', '\\u003c');
const html = `<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>列車素材檢視</title><style>body{margin:0;padding:12px;font:14px system-ui;background:#eceef6;color:#262c57}nav{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:8px}select,button{font:inherit;max-width:100%;padding:6px}canvas{width:100%;height:60vh;touch-action:none;background:#fff;border-radius:8px}pre{white-space:pre-wrap;overflow-wrap:anywhere}a{margin-right:12px}#downloads{display:flex;flex-wrap:wrap;gap:8px}</style>
<nav><select id="model"></select><select id="view"></select><select id="time"><option>day</option><option>night</option></select></nav>
<canvas id="canvas"></canvas><p>拖曳旋轉，滾輪或按鈕縮放。</p><nav><button id="in">放大</button><button id="out">縮小</button></nav>
<div id="downloads"></div><p id="meta"></p><p>WebGL 靜態預覽。遊戲接入、外觀接受及裝置驗證各自記錄於下方。</p><pre id="status"></pre>
<script>${scene}\n${renderer}\n
const models=${encode(models)},lighting=${encode(manifest.lighting)},status=${encode(status)};
const $=id=>document.getElementById(id),r=new NativeRenderer($('canvas'),lighting);
const fill=(id,values)=>{for(const value of values){const o=document.createElement('option');o.textContent=value;o.value=value;$(id).append(o)}};
fill('model',models.map(m=>m.id));fill('view',Object.keys(directions));$('view').value='isometric';
$('status').textContent=JSON.stringify(status,null,2);
let zoom=1,yaw=-Math.PI/4,pitch=.52,drag=null,orbit=false;
function draw(){const size=$('canvas').getBoundingClientRect();r.render($('view').value,{width:Math.round(size.width*devicePixelRatio),height:Math.round(size.height*devicePixelRatio),zoom,time:$('time').value,features:1,...(orbit?{vector:[Math.cos(yaw)*Math.cos(pitch),Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch)]}:{})});}
function load(){const m=models.find(m=>m.id===$('model').value),file=m.files.find(f=>f.kind==='native');r.load(Uint8Array.from(atob(file.data),c=>c.charCodeAt(0)).buffer);$('downloads').replaceChildren();
for(const f of m.files){const a=document.createElement('a');a.download=f.name;a.href='data:application/octet-stream;base64,'+f.data;a.textContent=f.kind;$('downloads').append(a)}
const png=document.createElement('a');png.textContent='PNG';png.download=m.id+'.png';png.onclick=()=>{draw();png.href=r.png()};$('downloads').append(png);
$('meta').textContent=m.id+' · '+(m.exported_triangles??m.triangles)+' triangles';zoom=1;orbit=false;draw();}
$('model').onchange=load;$('view').onchange=()=>{orbit=false;draw()};$('time').onchange=draw;
function scale(f){zoom=Math.max(.25,Math.min(4,zoom*f));draw()};$('in').onclick=()=>scale(1.15);$('out').onclick=()=>scale(1/1.15);
$('canvas').onwheel=e=>{e.preventDefault();scale(e.deltaY<0?1.1:1/1.1)};
$('canvas').onpointerdown=e=>{drag=[e.clientX,e.clientY];$('canvas').setPointerCapture(e.pointerId)};
$('canvas').onpointermove=e=>{if(!drag)return;yaw+=(e.clientX-drag[0])*.01;pitch=Math.max(-1.5,Math.min(1.5,pitch+(e.clientY-drag[1])*.01));drag=[e.clientX,e.clientY];orbit=true;draw()};
$('canvas').onpointerup=$('canvas').onpointercancel=()=>drag=null;window.onresize=draw;load();window.inspectorReady=true;
</script></html>`;
writeFileSync(resolve(out), html);
console.log(`wrote native inspector: ${models.length} models`);
