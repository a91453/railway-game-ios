#!/usr/bin/env node
// A look sheet of several native models, 800 px wide JPEG: each by day and by
// night at the game's camera angle, and at its size on an iPhone.
//   node sheet.mjs --title T --out sheet.jpg [--columns 3] [--zooms 400,600,800] [--heading 35] ID=file.m3dmodel=label ...
// Playwright as in tools/model-look/shoot.mjs (PLAYWRIGHT_MODULE, CHROMIUM_PATH).
import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {nightRenderer} from './night.mjs';
const args=process.argv.slice(2),option={columns:'3',zooms:'400,600,800',heading:'35',tilt:'42'},models=[];
for(let i=0;i<args.length;i++){if(args[i].startsWith('--')){option[args[i].slice(2)]=args[++i];}else{const [id,file,label]=args[i].split('=');models.push({id,file:resolve(file),label:label||id});}}
if(!models.length||!option.out){console.error('usage: sheet.mjs --title T --out sheet.jpg ID=file=label ...');process.exit(2);}
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const source=nightRenderer();
const server=createServer((req,res)=>{const path=new URL(req.url,'http://x').pathname;
 if(path==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta charset="utf-8"><canvas id="canvas" style="display:none"></canvas><main id="sheet"></main>');}
 if(path==='/renderer.js'){res.setHeader('Content-Type','text/javascript');return res.end(source);}
 const m=models.find(m=>'/'+m.id===path);if(!m){res.writeHead(404);return res.end();}res.end(readFileSync(m.file));});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||undefined,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
try{
 const page=await browser.newPage({viewport:{width:800,height:600},deviceScaleFactor:1});
 page.on('pageerror',e=>{throw e;});
 await page.goto('http://127.0.0.1:'+server.address().port+'/');
 await page.evaluate(async({title,models,columns,zooms,heading,tilt})=>{
  const {NativeRenderer}=await import('/renderer.js'),renderer=new NativeRenderer(document.getElementById('canvas'));
  const rad=d=>d*Math.PI/180,towards=(h,t)=>[Math.sin(rad(t))*Math.cos(rad(h)),Math.sin(rad(t))*Math.sin(rad(h)),Math.cos(rad(t))];
  function shot(buffer,h,t,width,height,night,pointsPerMetre){
   renderer.load(buffer);const d=towards(h,t),reference=Math.abs(d[2])>0.99?[0,1,0]:[0,0,1],cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],unit=a=>{const m=Math.hypot(...a);return a.map(x=>x/m);};
   const right=unit(cross(reference,d)),up=unit(cross(d,right)),projected=axis=>renderer.extent.reduce((s,v,i)=>s+Math.abs(axis[i])*v,0);
   const radius=Math.max(projected(up),projected(right)/(width/height),0.1)*1.14;
   renderer.render('',{width:width*2,height:height*2,vector:d,night});
   const image=new Image();image.src=renderer.png();
   image.style.width=(pointsPerMetre?Math.max(4,Math.round(width*pointsPerMetre*2*radius/height)):width)+'px';return image;
  }
  // Map3DCamera: 35 degrees of view up an 844-point screen; flat from 800 m, 42 degrees over at 120 m.
  const zoom=distance=>{const u=Math.min(1,Math.max(0,Math.log(800/distance)/Math.log(800/120)));return {distance,tilt:42*u*u*(3-2*u),points:844/(2*distance*Math.tan(rad(17.5)))};};
  const sheet=document.getElementById('sheet'),style=document.createElement('style');
  style.textContent='body{margin:0;background:#fff;font:12px system-ui,"PingFang TC";color:#262c57}#sheet{width:776px;padding:12px}h1{font-size:17px;margin:0 0 8px}.grid{display:grid;gap:8px}.cell{min-width:0;text-align:center}.day{background:#eceef6;border-radius:6px}.night{background:#171d33;border-radius:6px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:3px}.pair img{width:100%}.sizes{background:#eceef6;border-radius:6px;display:flex;align-items:center;justify-content:center;gap:8px;padding:4px;margin-top:3px;overflow:hidden;min-height:24px}.sizes img{flex:none;max-width:none}p{margin:2px 0}';
  document.head.append(style);
  const add=(tag,text,parent=sheet)=>{const e=document.createElement(tag);if(text)e.textContent=text;parent.append(e);return e;};
  add('h1',title);const grid=add('div');grid.className='grid';grid.style.gridTemplateColumns='repeat('+columns+',1fr)';
  for(const m of models){
   const buffer=await(await fetch('/'+m.id)).arrayBuffer(),cell=add('div','',grid);cell.className='cell';
   const pair=add('div','',cell);pair.className='pair';const w=Math.round(776/columns/2)-4,h=Math.round(w*0.8);
   for(const night of [0,1]){const image=shot(buffer,heading,tilt,w,h,night);image.className=night?'night':'day';pair.append(image);}
   if(zooms.length){const sizes=add('div','',cell);sizes.className='sizes';for(const z of zooms.map(zoom))sizes.append(shot(buffer,heading,z.tilt,200,200,0,z.points));}
   add('p',m.label,cell);
  }
  await Promise.all([...document.images].map(i=>i.decode()));
 },{title:option.title||'look sheet',models,columns:+option.columns,zooms:option.zooms==='none'?[]:option.zooms.split(',').map(Number),heading:+option.heading,tilt:+option.tilt});
 writeFileSync(resolve(option.out),await (await page.$('#sheet')).screenshot({type:'jpeg',quality:86}));
 console.log('Wrote '+option.out);
}finally{await browser.close();server.close();}
