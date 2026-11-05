import {readFileSync as read,writeFileSync as write} from 'node:fs';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]),manifest=JSON.parse(read(root+'/manifest.json'));
const hash=b=>createHash('sha256').update(b).digest('hex');
let renderer=read(new URL('../station-kit/renderer.js',import.meta.url),'utf8');
renderer=renderer.replace('precision highp float;in vec3 n,c;in float g;','precision highp float;uniform float night;in vec3 n,c;in float g;').replace('c*(0.8+0.2*sun)+vec3(g*0.025)','c*mix(0.8+0.2*sun,0.28+0.10*sun,night)+c*g*night*0.95').replace("'radius','aspect','depth'","'radius','aspect','depth','night'").replace('zoom=1,vector','zoom=1,vector,night=0').replace('Object.entries({radius,aspect,depth})','Object.entries({radius,aspect,depth,night})');
write(root+'/renderer.js',renderer);const script=renderer.replaceAll('export ','');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try{
 const page=await browser.newPage();await page.setContent('<canvas id="canvas"></canvas>');await page.addScriptTag({content:script+';window.renderer=new NativeRenderer(document.querySelector("canvas"));'});
 for(const m of manifest.models){
  const bytes=read(root+'/'+m.native),native=readNative(bytes);if(native.vertices.length/3!==m.triangles)throw Error(m.id+' count');
  m.glb=m.id+'/'+m.id+'.glb';write(root+'/'+m.glb,glbFromNative(native));m.sha256={native:hash(bytes),glb:hash(read(root+'/'+m.glb))};m.views={};
  for(const state of ['day','night'])for(const direction of manifest.directions){
   const png=await page.evaluate(({b,d,n})=>{renderer.load(Uint8Array.from(atob(b),c=>c.charCodeAt(0)).buffer);renderer.render(d,{width:512,height:512,night:n});return renderer.png()}, {b:bytes.toString('base64'),d:direction,n:state==='night'?1:0});
   const file=m.id+'/'+state+'-'+direction+'.png';write(root+'/'+file,Buffer.from(png.split(',')[1],'base64'));m.views[state+'-'+direction]=file;
  }
 }
 // The eight variants share the same native geometry, fixed camera and
 // pixel dimensions, so these PNGs are directly comparable at one scale.
 const near=manifest.models.filter(m=>!m.far);
 for(const state of ['day','night']){
  await page.setViewportSize({width:1690,height:500});
  await page.setContent('<meta charset="utf-8"><style>body{font:17px system-ui;background:#eceef6;color:#26385c;margin:20px}main{display:grid;grid-template-columns:repeat(8,1fr);gap:8px}article{background:white;border-radius:8px;padding:4px;text-align:center}img{width:100%}</style><h1>國道客運車隊 · '+state+' · 同尺度</h1><main>'+near.map(m=>'<article><img src="data:image/png;base64,'+read(root+'/'+m.views[state+'-isometric']).toString('base64')+'"><div>'+m.name_zh+'</div></article>').join('')+'</main>');
  await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
  await page.screenshot({path:root+'/fleet-'+state+'.png',fullPage:true});
 }
 write(root+'/manifest.json',JSON.stringify(manifest,null,2)+'\n');
 const embedded=manifest.models.map(m=>({id:m.id,name:m.name_zh+' / '+m.name_en,triangles:m.triangles,bytes:read(root+'/'+m.native).toString('base64')}));
 const html=`<!doctype html><meta charset="utf-8"><title>客運車塗裝 studies</title><style>body{font:16px system-ui;background:#eceef6;color:#26385c;margin:16px}canvas{display:block;width:100%;height:70vh;touch-action:none;background:white}select,button{font:inherit;margin:5px}</style><h1>國道客運車塗裝 · studies</h1><p>拖曳旋轉、滾輪縮放。外觀待作者確認。</p><select id="model"></select><select id="view">${manifest.directions.map(d=>'<option>'+d+'</option>').join('')}</select><button id="night">日／夜</button><canvas id="canvas"></canvas><p id="info"></p><script>${script}\nconst models=${JSON.stringify(embedded)},model=document.querySelector('#model'),view=document.querySelector('#view'),canvas=document.querySelector('#canvas'),r=new NativeRenderer(canvas);let night=0,zoom=1,vector,angle=0,elevation=.6;models.forEach((m,i)=>model.add(new Option(m.name+(m.id.endsWith('far')?' · 遠景':' · 近景'),i)));view.value='isometric';function draw(){const m=models[model.value||0];r.load(Uint8Array.from(atob(m.bytes),c=>c.charCodeAt(0)).buffer);r.render(view.value,{width:1000,height:650,night,zoom,vector});document.querySelector('#info').textContent=m.name+' · '+m.triangles+' triangles'}model.onchange=()=>{zoom=1;draw()};view.onchange=()=>{vector=undefined;draw()};document.querySelector('#night').onclick=()=>{night=1-night;draw()};canvas.onwheel=e=>{e.preventDefault();zoom=Math.max(.3,Math.min(3,zoom*Math.exp(-e.deltaY*.001)));draw()};let drag;canvas.onpointerdown=e=>{drag=[e.clientX,e.clientY];canvas.setPointerCapture(e.pointerId)};canvas.onpointerup=()=>drag=null;canvas.onpointermove=e=>{if(!drag)return;angle+=(e.clientX-drag[0])*.01;elevation=Math.max(-1.4,Math.min(1.4,elevation+(e.clientY-drag[1])*.01));drag=[e.clientX,e.clientY];vector=[Math.cos(angle),Math.sin(angle),elevation];draw()};draw();</script>`;
 write(root+'/viewer.html',html);
 const img=(m,v)=>'data:image/png;base64,'+read(root+'/'+m.views[v]).toString('base64');
 async function sheet(file,title,models,dirs){await page.setViewportSize({width:1350,height:700});await page.setContent('<meta charset="utf-8"><style>body{font:18px system-ui;background:#eceef6;color:#26385c;margin:20px}main{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}article{background:white;padding:9px;border-radius:10px}img{width:100%}</style><h1>'+title+'</h1><main>'+models.flatMap(m=>dirs.map(d=>'<article><img src="'+img(m,d)+'"><div>'+m.name_zh+' / '+d+'</div></article>')).join('')+'</main>');await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:root+'/'+file,fullPage:true})}
 await sheet('overview.png','國道客運塗裝 · 日夜車隊自檢',near,['day-isometric','night-isometric']);
 await sheet('directions.png','八種塗裝 · 七方向自檢',near,manifest.directions.map(d=>'day-'+d));
 const farModels=manifest.models.filter(m=>m.far);
 await page.setViewportSize({width:1000,height:600});
 await page.setContent('<meta charset="utf-8"><style>body{font:18px system-ui;background:#eceef6;color:#26385c;margin:20px}main{display:grid;grid-template-columns:repeat(4,1fr);gap:15px}article{height:145px;background:white;border-radius:10px;text-align:center;padding:8px}img{width:64px;height:64px}</style><h1>遠景 64 px · 配色辨識自檢</h1><main>'+farModels.map(m=>'<article><img src="'+img(m,'day-isometric')+'"><div>'+m.name_zh+'</div></article>').join('')+'</main>');
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
 await page.screenshot({path:root+'/far-small.png',fullPage:true});
 console.log('Rendered',manifest.models.length,'models and 224 views');
}finally{await browser.close()}
