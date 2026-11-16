#!/usr/bin/env node
// tools/model-look: the Christmas livery options (WINTER-LIVERY-2, decision 806)
// as export-winter.sh options wrote them, in two kinds of picture:
//
//   node tools/model-look/shoot-livery.mjs --dir EXPORTED --out FOLDER [--only game|table|nose]
//
// The columns are options.json's `variants`, headed by its `labels` where it
// has them (pair-livery.sh puts two exports side by side so).
//
//   table-day.jpg, table-night.jpg   each train's first two cars enlarged: plain | A1 | A2 | A3 | A2 with A1's ribbon
//   nose-day.jpg, nose-night.jpg     each train's head car's front up close, at the 250 m camera's
//     tilt (29°) and from higher (60°): where the wreath lies (WREATH-NOSE)
//   game-day.jpg, game-night.jpg     the train on a track at the size an iPhone draws it
//     (1 px = 1 point, Map3DCamera: 35° of view up 844 points), the camera 250 m,
//     400 m and 700 m away at the tilt it has there (29°, 13°, straight down);
//     at 700 m the far set, as the game draws it past 500 m.
//
// The drawing is tools/station-kit/renderer.js (orthographic WebGL, the game's flat
// model light): not Metal, not the app. Night: the exporter darkened what is not
// lit; round each lamp and bulb (NAME-night-mask) a glow is added the size
// Map3DGlow gives a light 0.3 m across (0.9 m), which the game adds too.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';

const here=dirname(fileURLToPath(import.meta.url)),args=process.argv.slice(2),option={};
for(let i=0;i<args.length;i+=2)option[args[i].replace(/^--/,'')]=args[i+1];
if(!option.dir||!option.out){console.error('usage: shoot-livery.mjs --dir EXPORTED --out FOLDER [--only game|table|nose]');process.exit(2);}
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const manifest=JSON.parse(readFileSync(resolve(option.dir,'options.json'),'utf8'));
mkdirSync(resolve(option.out),{recursive:true});
const server=createServer((req,res)=>{const path=new URL(req.url,'http://x').pathname;
 if(path==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta charset="utf-8"><canvas id="canvas" style="display:none"></canvas><main id="sheet"></main>');}
 if(path==='/renderer.js'){res.setHeader('Content-Type','text/javascript');return res.end(readFileSync(resolve(here,'../station-kit/renderer.js')));}
 try{const data=readFileSync(resolve(option.dir,'.'+path));res.setHeader('Content-Type','application/octet-stream');res.end(data);}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||undefined,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
const names={plain:'原塗裝',a1:'A1 緞帶',a2:'A2 雪頂',a3:'A3 腰帶＋雪頂',mix:'A2＋頭車緞帶',...(manifest.labels||{})};
try{
 for(const kind of ['table','nose','game'])for(const night of [false,true]){
  if(option.only&&option.only!==kind)continue;
  const page=await browser.newPage({viewport:{width:kind==='table'?1640:kind==='nose'?60+manifest.variants.length*244+20:800,height:600},deviceScaleFactor:1});
  page.on('pageerror',e=>{throw e;});
  await page.goto('http://127.0.0.1:'+server.address().port+'/');
  await page.evaluate(async({manifest,names,kind,night})=>{
   const {NativeRenderer}=await import('/renderer.js'),renderer=new NativeRenderer(document.getElementById('canvas'));renderer.maximumTriangles=600000;
   const rad=d=>d*Math.PI/180,unit=a=>{const m=Math.hypot(...a);return a.map(x=>x/m);},cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
   // From the model towards the camera: `tilt` from straight down, `heading` round from its front towards its left.
   const towards=(heading,tilt)=>[Math.sin(rad(tilt))*Math.cos(rad(heading)),Math.sin(rad(tilt))*Math.sin(rad(heading)),Math.cos(rad(tilt))];
   const load=async name=>renderer.load(await(await fetch('/'+name+'.m3dmodel')).arrayBuffer());
   // One picture `width` by `height` points, drawn at twice that; `frame` {centre, metres up the picture} or the whole model.
   async function draw(name,vector,width,height,frame){
    await load(name);let zoom=1;
    if(frame){renderer.centre=frame.centre;renderer.extent=[90,90,90];
     const d=unit(vector),reference=Math.abs(d[2])>0.99?[0,1,0]:[0,0,1],right=unit(cross(reference,d)),up=unit(cross(d,right)),projected=axis=>axis.reduce((s,v)=>s+Math.abs(v)*90,0);
     zoom=Math.max(projected(up),projected(right)/(width/height),0.1)*1.14/(frame.metres/2);}
    renderer.render('',{width:width*2,height:height*2,vector,zoom});
    const image=new Image();image.src=renderer.png();await image.decode();return image;
   }
   // By night: the darkened picture, and round what glows a glow `glow` points wide.
   async function shot(name,vector,width,height,frame,glow){
    if(!night)return styled(await draw(name,vector,width,height,frame),width);
    const base=await draw(name+'-night',vector,width,height,frame),mask=await draw(name+'-night-mask',vector,width,height,frame);
    const canvas=document.createElement('canvas');canvas.width=width*2;canvas.height=height*2;const c=canvas.getContext('2d');
    c.fillStyle='#10152e';c.fillRect(0,0,canvas.width,canvas.height);c.drawImage(base,0,0);c.globalCompositeOperation='lighter';
    c.filter='blur('+Math.max(1,glow*2*0.45)+'px)';for(let i=0;i<3;i++)c.drawImage(mask,0,0);c.filter='blur('+Math.max(0.6,glow*2*0.15)+'px)';c.drawImage(mask,0,0);c.drawImage(mask,0,0);c.filter='none';
    return styled(canvas,width);
   }
   const styled=(element,width)=>{element.style.width=width+'px';element.style.display='block';return element;};
   const sheet=document.getElementById('sheet'),style=document.createElement('style');
   style.textContent='body{margin:0;background:'+(night?'#10152e':'#fff')+';font:13px system-ui,"PingFang TC","Noto Sans CJK TC";color:'+(night?'#e8eaf6':'#262c57')+'}#sheet{padding:10px;width:'+(kind==='table'?1620:kind==='nose'?60+manifest.variants.length*244:780)+'px}h1{font-size:16px;margin:0 0 4px}h2{font-size:13px;margin:10px 0 4px}p{margin:2px 0;font-size:11px}.row{display:flex;gap:4px;margin-bottom:4px;align-items:center}.cell{background:'+(night?'#10152e':'#eceef6')+';border-radius:5px;overflow:hidden;flex:none}.head{display:flex;gap:4px}.head div{text-align:center;font-weight:600;flex:none}.label{width:56px;flex:none;font-size:11px}';
   document.head.append(style);
   const add=(tag,text,parent=sheet)=>{const e=document.createElement(tag);if(text)e.textContent=text;parent.append(e);return e;};
   const header=width=>{const h=add('div');h.className='head';add('div','',h).style.width='56px';for(const v of manifest.variants)add('div',names[v],h).style.width=width+'px';};
   if(kind==='table'){
    add('h1','聖誕塗裝方案（'+(night?'夜晚':'白天')+'，放大）：每款頭車與第二節｜第 '+manifest.round+' 輪');
    add('p','離線 WebGL，不是 Metal。'+(night?'夜晚是示意：不發光的面壓暗，車窗與頭燈照遊戲的規則亮，燈泡外加光暈。':''));
    header(304);
    for(const t of manifest.trains){const row=add('div');row.className='row';add('div',t.label,row).className='label';
     for(const v of manifest.variants){const cell=add('div','',row);cell.className='cell';cell.append(await shot(t.id+'-'+v+'-pair',towards(62,52),304,146,null,5));}}
   }else if(kind==='nose'){
    add('h1','頭車車頭近看（'+(night?'夜晚':'白天')+'）：上排傾 29°（250 m 的鏡頭），下排傾 60°｜第 '+manifest.round+' 輪');
    add('p','離線 WebGL，不是 Metal。只用來找毛病；遊戲大小看 game-*.jpg。');
    header(240);
    for(const t of manifest.trains)for(const tilt of [29,60]){const row=add('div');row.className='row';add('div',tilt===29?t.label:'',row).className='label';
     for(const v of manifest.variants){const cell=add('div','',row);cell.className='cell';cell.append(await shot(t.id+'-'+v+'-pair',towards(32,tilt),240,130,{centre:[-3.5,0,2],metres:9},4));}}
   }else{
    add('h1','聖誕塗裝方案（'+(night?'夜晚':'白天')+'，遊戲實際大小）：1 px = iPhone 的 1 點｜第 '+manifest.round+' 輪');
    add('p','鏡頭照 Map3DCamera：距離 250 m 傾 29°、400 m 傾 13°、700 m 正上方（換成遠景版）。離線 WebGL，不是 Metal。瞇眼看：一秒內分得出是聖誕車嗎？還認得出哪條線嗎？');
    const zooms=[250,400,700].map(distance=>{const u=Math.min(1,Math.max(0,Math.log(800/distance)/Math.log(800/120)));return {distance,tilt:42*u*u*(3-2*u),points:844/(2*distance*Math.tan(rad(17.5)))};});
    for(const z of zooms){
     const far=z.distance>500,height=z.distance===250?112:z.distance===400?84:46,width=140;
     add('h2','鏡頭 '+z.distance+' m（1 m = '+z.points.toFixed(1)+' 點，傾 '+z.tilt.toFixed(0)+'°'+(far?'，遠景版':'')+'）');header(width);
     for(const t of manifest.trains){const row=add('div');row.className='row';add('div',t.label,row).className='label';
      const centre=far?[-38,0,1.5]:z.distance===400?[-13,1,1.5]:[-11,1,1.5];
      for(const v of manifest.variants){const cell=add('div','',row);cell.className='cell';cell.append(await shot(t.id+'-'+v+(far?'-far':'-scene'),towards(far?90:32,z.tilt),width,height,{centre,metres:height/z.points},0.9*z.points));}}
    }
   }
  },{manifest,names,kind,night});
  const file=resolve(option.out,kind+'-'+(night?'night':'day')+'.jpg');
  writeFileSync(file,await (await page.$('#sheet')).screenshot({type:'jpeg',quality:85}));
  console.log('Wrote '+file);await page.close();
 }
}finally{await browser.close();server.close();}
