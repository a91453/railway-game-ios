#!/usr/bin/env node
// tools/model-look: the look sheet of one native model (.m3dmodel), 800 px
// wide JPEG: the model at the game's camera angles and on-screen sizes,
// enlarged, on the map's ground among the city's plain blocks, and beside
// real photos; with --before, the earlier model in the same shots. .claude/skills/model-look/SKILL.md says how to read it.
//
//   node tools/model-look/shoot.mjs --model new.m3dmodel [--before old.m3dmodel]
//     [--photo 'file.jpg|caption|heading|elevation']... [--focus cx,cy,cz,ex,ey,ez] [--labels 改前,改後] [--title text] [--max-triangles n] --out sheet.jpg
//
// heading: degrees round the model from its front (native +x), towards its
// left (+y); elevation: degrees above the ground. --focus: the box (centre
// and half sizes, native metres) parts two and three frame, when the model
// carries a forecourt or platforms that would make its building small.
// --max-triangles: for a scene of several models (a museum with its exhibits),
// more than the 15,000 one native model may have. The drawing is
// tools/station-kit/renderer.js (orthographic, the game's flat model light).
// Playwright: `playwright` on NODE_PATH, or PLAYWRIGHT_MODULE=<its folder>;
// CHROMIUM_PATH names a browser other than Playwright's own.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';

const here=dirname(fileURLToPath(import.meta.url)),args=process.argv.slice(2),option={photo:[]};
for(let i=0;i<args.length;i+=2){const k=args[i].replace(/^--/,'');if(k==='photo')option.photo.push(args[i+1]);else option[k]=args[i+1];}
if(!option.model||!option.out){console.error('usage: shoot.mjs --model M [--before M] [--photo "file|caption|heading|elevation"]... [--focus cx,cy,cz,ex,ey,ez] [--title T] --out sheet.jpg');process.exit(2);}
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const files={'/renderer.js':resolve(here,'../station-kit/renderer.js'),'/after.m3dmodel':resolve(option.model)};
if(option.before)files['/before.m3dmodel']=resolve(option.before);
const photos=option.photo.map((p,i)=>{const [file,caption,heading,elevation]=p.split('|');files['/photo'+i+extname(file)]=resolve(file);return {src:'/photo'+i+extname(file),caption,heading:+heading,elevation:+elevation};});
const mime={'.js':'text/javascript','.jpg':'image/jpeg','.jpeg':'image/jpeg','.png':'image/png'};
const server=createServer((req,res)=>{const f=files[new URL(req.url,'http://x').pathname];if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta charset="utf-8"><canvas id="canvas" style="display:none"></canvas><main id="sheet"></main>');}
 if(!f){res.writeHead(404);return res.end();}res.setHeader('Content-Type',mime[extname(f)]||'application/octet-stream');res.end(readFileSync(f));});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||undefined,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
try{
 const page=await browser.newPage({viewport:{width:800,height:600},deviceScaleFactor:1});
 page.on('pageerror',e=>{throw e;});
 await page.goto('http://127.0.0.1:'+server.address().port+'/');
 await page.evaluate(async({title,photos,hasBefore,focus,labels,most})=>{
  const {NativeRenderer}=await import('/renderer.js'),renderer=new NativeRenderer(document.getElementById('canvas'));if(most)renderer.maximumTriangles=most;
  const models={};for(const name of hasBefore?['before','after']:['after'])models[name]=await(await fetch('/'+name+'.m3dmodel')).arrayBuffer();
  const rad=d=>d*Math.PI/180;
  // What the 3D map draws round a model, as Map3DLook leaves them (decisions 370 and 451):
  // Map3DPalette.ground (#ECEEF6 once this renderer's light is on it), a tertiary road and its kerb, and a city block's wall (tileWhite)
  // and roof as tools/map3d-preview draws them by day (a wall with its windows L* 61, a roof
  // L* 86: docs/art/map3d-liveliness-2026-11-13). Change them here when the map's look changes.
  const rgb=hex=>(0xFF000000|(hex&255)<<16|hex&0xFF00|hex>>>16)>>>0,MAP={ground:rgb(0xF7F9FF),road:rgb(0xA09FAA),kerb:rgb(0xF7F7F4),wall:rgb(0xA3A7B0),roof:rgb(0xE0E2E8)};
  // From the model towards the camera: `tilt` from straight down, as the game's camera counts it.
  const towards=(heading,tilt)=>[Math.sin(rad(tilt))*Math.cos(rad(heading)),Math.sin(rad(tilt))*Math.sin(rad(heading)),Math.cos(rad(tilt))];
  // One picture; `pointsPerMetre` gives it its size on an iPhone at that zoom, else it fills `width`.
  function shot(name,heading,tilt,width,height,pointsPerMetre){
   renderer.load(models[name]);if(focus&&!pointsPerMetre){renderer.centre=focus.slice(0,3);renderer.extent=focus.slice(3);}const vector=towards(heading,tilt),n=Math.hypot(...vector),d=vector.map(x=>x/n);
   const reference=Math.abs(d[2])>0.99?[0,1,0]:[0,0,1],cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],unit=a=>{const m=Math.hypot(...a);return a.map(x=>x/m);};
   const right=unit(cross(reference,d)),up=unit(cross(d,right)),projected=axis=>renderer.extent.reduce((s,v,i)=>s+Math.abs(axis[i])*v,0);
   const radius=Math.max(projected(up),projected(right)/(width/height),0.1)*1.14;
   renderer.render('',{width:width*2,height:height*2,vector});
   const image=new Image();image.src=renderer.png();
   if(pointsPerMetre){const scale=pointsPerMetre*2*radius/height;image.style.width=Math.max(4,Math.round(width*scale))+'px';}else image.style.width=width+'px';
   return image;
  }
  // Map3DCamera: 35° of view up an 844-point screen; flat from 800 m, 42° over at 120 m.
  const zooms=[400,600,800].map(distance=>{const u=Math.min(1,Math.max(0,Math.log(800/distance)/Math.log(800/120)));return {distance,tilt:42*u*u*(3-2*u),points:844/(2*distance*Math.tan(rad(17.5)))};});
  const sheet=document.getElementById('sheet'),names=Object.keys(models),label=labels?{before:labels[0],after:labels[1]||labels[0]}:{before:'改前',after:names.length>1?'改後':'模型'};
  const style=document.createElement('style');style.textContent='body{margin:0;background:#fff;font:13px system-ui,"PingFang TC";color:#262c57}#sheet{width:776px;padding:12px}h1{font-size:17px;margin:0 0 6px}h2{font-size:14px;margin:12px 0 4px}.row{display:flex;gap:8px;align-items:flex-end}.cell{flex:1;min-width:0;text-align:center}.ground{background:#eceef6;border-radius:6px;display:flex;align-items:center;justify-content:center;gap:10px;padding:6px;overflow:hidden;margin-bottom:6px}.ground img{max-width:none;flex:none}.big{background:#eceef6;border-radius:6px}.cell img{max-width:100%}.photo img{width:100%;border-radius:6px}p{margin:2px 0;font-size:12px}';document.head.append(style);
  const add=(tag,text,parent=sheet)=>{const e=document.createElement(tag);if(text)e.textContent=text;parent.append(e);return e;};
  add('h1',title);
  add('h2','一、遊戲裡的大小（iPhone 直放，1 格 = 1 點；鏡頭 400／600／800 m）');
  let row;
  for(const name of names){const ground=add('div');ground.className='ground';add('p',label[name],ground).style.width='40px';
   for(const z of zooms)ground.append(shot(name,35,z.tilt,300,300,z.points));}
  add('h2','二、遊戲鏡頭角度放大（傾 40°；站前斜看、月台側斜看）');
  for(const heading of [35,215]){row=add('div');row.className='row';
   for(const name of names){const cell=add('div','',row);cell.className='cell';const w=names.length>1?380:560;const image=shot(name,heading,40,w,Math.round(w*0.62));image.className='big';cell.append(image);add('p',label[name]+(heading===35?'｜站前':'｜月台側'),cell);}}
  // The model where the map draws it: on the game's ground, a road in front and three
  // of the city's plain blocks round it (MAP, above), in colour and in grey.
  function placed(buffer){
   const d=new DataView(buffer),count=d.getUint32(8,true),start=16+Math.ceil(d.getUint32(12,true)/4)*4,triangles=[];
   const quad=(a,b,c,e,colour)=>triangles.push([a,b,c,colour],[a,c,e,colour]);
   const box=(x0,y0,x1,y1,z0,z1,wall,roof)=>{const p=(x,y,z)=>[x,y,z];
    quad(p(x0,y0,z1),p(x1,y0,z1),p(x1,y1,z1),p(x0,y1,z1),roof);quad(p(x1,y0,z0),p(x1,y1,z0),p(x1,y1,z1),p(x1,y0,z1),wall);quad(p(x0,y1,z0),p(x0,y0,z0),p(x0,y0,z1),p(x0,y1,z1),wall);
    quad(p(x1,y1,z0),p(x0,y1,z0),p(x0,y1,z1),p(x1,y1,z1),wall);quad(p(x0,y0,z0),p(x1,y0,z0),p(x1,y0,z1),p(x0,y0,z1),wall);};
   renderer.load(buffer);const c=focus?focus.slice(0,3):renderer.centre,e=focus?focus.slice(3):renderer.extent,z=renderer.bounds.low[2],reach=Math.max(e[0],e[1])+46;
   quad([c[0]-reach*3,c[1]-reach*3,z-0.06],[c[0]+reach*3,c[1]-reach*3,z-0.06],[c[0]+reach*3,c[1]+reach*3,z-0.06],[c[0]-reach*3,c[1]+reach*3,z-0.06],MAP.ground);
   const front=c[0]+e[0]+5;box(front,c[1]-reach*3,front+1.6,c[1]+reach*3,z-0.05,z+0.12,MAP.kerb,MAP.kerb);box(front+1.6,c[1]-reach*3,front+11.6,c[1]+reach*3,z-0.05,z+0.02,MAP.road,MAP.road);
   box(c[0]-e[0]-22,c[1]+e[1]*0.1,c[0]-e[0]-6,c[1]+e[1]*0.1+22,z,z+21,MAP.wall,MAP.roof);
   box(c[0]-e[0]*0.4,c[1]+e[1]+6,c[0]-e[0]*0.4+14,c[1]+e[1]+20,z,z+10.5,MAP.wall,MAP.roof);
   box(c[0]-e[0]*0.2-6,c[1]-e[1]-22,c[0]-e[0]*0.2+12,c[1]-e[1]-6,z,z+14,MAP.wall,MAP.roof);
   const out=new ArrayBuffer(start+(count+triangles.length)*52),bytes=new Uint8Array(out),view=new DataView(out);bytes.set(new Uint8Array(buffer));view.setUint32(8,count+triangles.length,true);
   triangles.forEach((t,i)=>{const at=start+(count+i)*52;view.setUint32(at,0,true);for(let j=0;j<3;j++){const k=at+4+j*16;t[j].forEach((x,n)=>view.setFloat32(k+n*4,x,true));view.setUint32(k+12,t[3],true);}});
   return {buffer:out,centre:[c[0],c[1],z+Math.max(e[2],10)],extent:[e[0]+24,e[1]+24,Math.max(e[2],10)]};
  }
  function onMap(name,width,height,grey){
   const scene=placed(models[name]),before=renderer.maximumTriangles;renderer.maximumTriangles=Math.max(before||15000,15000)+64;renderer.load(scene.buffer);renderer.maximumTriangles=before;
   renderer.centre=scene.centre;renderer.extent=scene.extent;renderer.render('',{width:width*2,height:height*2,vector:towards(35,40)});
   const image=new Image();image.src=renderer.png();image.style.width=width+'px';image.className='big';if(grey)image.style.filter='grayscale(1)';return image;
  }
  add('h2','三、放在地圖上的樣子（遊戲的地面色、三棟城市建築的通用方塊、一條路；右邊是灰階）');
  for(const name of names){row=add('div');row.className='row';
   for(const grey of [false,true]){const cell=add('div','',row);cell.className='cell';cell.append(onMap(name,380,236,grey));add('p',label[name]+(grey?'｜灰階：屋頂、牆、地面還分得開嗎':'｜和背景分得開嗎'),cell);}}
  if(photos.length)add('h2','四、和真實照片並排（同方向；照片只供比對形狀與顏色）');
  for(const photo of photos){row=add('div');row.className='row';
   const cell=add('div','',row);cell.className='cell photo';const image=add('img','',cell);image.src=photo.src;add('p',photo.caption,cell);
   for(const name of names){const c=add('div','',row);c.className='cell';const w=names.length>1?250:380;const m=shot(name,photo.heading,90-photo.elevation,w,Math.round(w*0.7));m.className='big';c.append(m);add('p',label[name],c);}}
  await Promise.all([...document.images].map(i=>i.decode()));
 },{title:option.title||'model look',photos,hasBefore:!!option.before,focus:option.focus?option.focus.split(',').map(Number):null,labels:option.labels?option.labels.split(','):null,most:+option['max-triangles']||0});
 writeFileSync(resolve(option.out),await (await page.$('#sheet')).screenshot({type:'jpeg',quality:86}));
 console.log('Wrote '+option.out+' (800 px wide)');
}finally{await browser.close();server.close();}
