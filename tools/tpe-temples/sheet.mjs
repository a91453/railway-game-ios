#!/usr/bin/env node
// Decision 725: one 800 px wide sheet of several temples, for looking
// (model-look): each temple at the game's camera angle (40° from straight
// down) from the south-east, at its size on an iPhone at 300 m, and beside
// it the same model from straight above at 600 m on the map's ground.
// Optional photos (`--photo id=file.jpg`) go in a third column.
//
//   node tools/tpe-temples/sheet.mjs --out sheet.jpg [--title T] [--photo id=file]... a.m3dmodel b.m3dmodel ...
//
// Drawn by tools/station-kit/renderer.js (orthographic, the game's flat
// model light), as tools/model-look/shoot.mjs; not Metal.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname,extname,basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';

const here=dirname(fileURLToPath(import.meta.url)),args=process.argv.slice(2),models=[],photos={};let out,title='temples';
for(let i=0;i<args.length;i++){if(args[i]==='--out')out=args[++i];else if(args[i]==='--title')title=args[++i];else if(args[i]==='--photo'){const [id,f]=args[++i].split('=');photos[id]=f;}else models.push(args[i]);}
if(!out||!models.length){console.error('usage: sheet.mjs --out sheet.jpg [--title T] [--photo id=file]... model.m3dmodel...');process.exit(2);}
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const files={'/renderer.js':resolve(here,'../station-kit/renderer.js')},list=[];
models.forEach((m,i)=>{const id=basename(m,'.m3dmodel');files['/m'+i+'.m3dmodel']=resolve(m);const entry={id,src:'/m'+i+'.m3dmodel'};if(photos[id]){files['/p'+i+extname(photos[id])]=resolve(photos[id]);entry.photo='/p'+i+extname(photos[id]);}list.push(entry);});
const mime={'.js':'text/javascript','.jpg':'image/jpeg','.jpeg':'image/jpeg','.png':'image/png'};
const server=createServer((req,res)=>{const f=files[new URL(req.url,'http://x').pathname];if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta charset="utf-8"><canvas id="canvas" style="display:none"></canvas><main id="sheet"></main>');}
 if(!f){res.writeHead(404);return res.end();}res.setHeader('Content-Type',mime[extname(f)]||'application/octet-stream');res.end(readFileSync(f));});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||undefined,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
try{
 const page=await browser.newPage({viewport:{width:800,height:600},deviceScaleFactor:1});
 page.on('pageerror',e=>{throw e;});
 await page.goto('http://127.0.0.1:'+server.address().port+'/');
 await page.evaluate(async({title,list})=>{
  const {NativeRenderer}=await import('/renderer.js'),renderer=new NativeRenderer(document.getElementById('canvas'));renderer.maximumTriangles=40000;
  const rad=d=>d*Math.PI/180,rgb=hex=>(0xFF000000|(hex&255)<<16|hex&0xFF00|hex>>>16)>>>0,GROUND=rgb(0xE4E3DF);
  const towards=(heading,tilt)=>[Math.sin(rad(tilt))*Math.cos(rad(heading)),Math.sin(rad(tilt))*Math.sin(rad(heading)),Math.cos(rad(tilt))];
  // The model on a ground square (its own ground at z 0).
  function onGround(buffer){
   const d=new DataView(buffer),count=d.getUint32(8,true),start=16+Math.ceil(d.getUint32(12,true)/4)*4;renderer.load(buffer);
   const c=renderer.centre,e=renderer.extent,r=Math.max(e[0],e[1])*3+40,q=[[c[0]-r,c[1]-r,-0.05],[c[0]+r,c[1]-r,-0.05],[c[0]+r,c[1]+r,-0.05],[c[0]-r,c[1]+r,-0.05]];
   const tris=[[q[0],q[1],q[2]],[q[0],q[2],q[3]]],o=new ArrayBuffer(start+(count+2)*52),v=new DataView(o);new Uint8Array(o).set(new Uint8Array(buffer));v.setUint32(8,count+2,true);
   tris.forEach((t,i)=>{const at=start+(count+i)*52;v.setUint32(at,0,true);for(let j=0;j<3;j++){const k=at+4+j*16;t[j].forEach((x,n)=>v.setFloat32(k+n*4,x,true));v.setUint32(k+12,GROUND,true);}});
   return {buffer:o,centre:c,extent:e};
  }
  function shot(buffer,heading,tilt,width,height,pointsPerMetre,ground){
   const scene=ground?onGround(buffer):null;renderer.load(scene?scene.buffer:buffer);if(scene){renderer.centre=scene.centre;renderer.extent=scene.extent;}
   const vector=towards(heading,tilt),n=Math.hypot(...vector),dir=vector.map(x=>x/n);
   const reference=Math.abs(dir[2])>0.99?[0,1,0]:[0,0,1],cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],unit=a=>{const m=Math.hypot(...a);return a.map(x=>x/m);};
   const right=unit(cross(reference,dir)),up=unit(cross(dir,right)),projected=axis=>renderer.extent.reduce((s,v,i)=>s+Math.abs(axis[i])*v,0);
   const radius=Math.max(projected(up),projected(right)/(width/height),0.1)*1.14;
   renderer.render('',{width:width*2,height:height*2,vector});const image=new Image();image.src=renderer.png();
   image.style.width=(pointsPerMetre?Math.max(4,Math.round(width*pointsPerMetre*2*radius/height)):width)+'px';return image;
  }
  const points=d=>844/(2*d*Math.tan(rad(17.5)));
  const style=document.createElement('style');style.textContent='body{margin:0;background:#fff;font:12px system-ui,"PingFang TC";color:#262c57}#sheet{width:776px;padding:12px}h1{font-size:16px;margin:0 0 6px}.row{display:flex;gap:6px;align-items:center;margin-bottom:6px}.cell{flex:1;min-width:0;text-align:center;background:#eceef6;border-radius:6px;padding:4px;height:200px;display:flex;flex-direction:column;align-items:center;justify-content:center}.cell img{max-width:100%;max-height:170px}.small{flex:0 0 120px}p{margin:2px 0}';document.head.append(style);
  const sheet=document.getElementById('sheet'),add=(tag,text,parent=sheet)=>{const e=document.createElement(tag);if(text)e.textContent=text;parent.append(e);return e;};
  add('h1',title);
  for(const m of list){
   const buffer=await(await fetch(m.src)).arrayBuffer(),row=add('div');row.className='row';
   const a=add('div','',row);a.className='cell';a.append(shot(buffer,-50,40,330,200));add('p',m.id+'｜遊戲鏡頭 40°，東南方',a);
   const b=add('div','',row);b.className='cell small';b.append(shot(buffer,-90,30,300,300,points(300),true));add('p','300 m 的大小',b);
   const c=add('div','',row);c.className='cell small';c.append(shot(buffer,-90,0.5,300,300,points(600),true));add('p','600 m 正上方',c);
   if(m.photo){const p=add('div','',row);p.className='cell';const i=add('img','',p);i.src=m.photo;add('p','照片',p);}
  }
  await Promise.all([...document.images].map(i=>i.decode()));
 },{title,list});
 writeFileSync(resolve(out),await (await page.$('#sheet')).screenshot({type:'jpeg',quality:86}));
 console.log('Wrote '+out);
}finally{await browser.close();server.close();}
