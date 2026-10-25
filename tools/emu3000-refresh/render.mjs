// Render ONLY exported native units and exact native assemblies. No image generation.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync,existsSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)('playwright'),source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex');
let renderer=readFileSync(resolve(source,'scene.js'),'utf8').replace('export function assemblyNative','function assemblyNative')+'\n'+readFileSync(resolve(source,'../station-kit/renderer.js'),'utf8').replace(' load(buffer){',' prepare(buffer){return assemblyNative(buffer);}\n load(buffer){buffer=assemblyNative(buffer);').replace('count>15000','count>200000');
renderer=renderer.replace('zoom=1,vector}={}','zoom=1,vector,metresPerPixel}={}').replace('const radius=Math.max(','const radius=metresPerPixel ? height*metresPerPixel/2/zoom : Math.max(');
writeFileSync(resolve(root,'renderer.js'),renderer);copyFileSync(resolve(source,'viewer.html'),resolve(root,'index.html'));
writeFileSync(resolve(root,'_render.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const address='http://127.0.0.1:'+server.address().port;let browser;
try {
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1500,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 async function stage(){await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);}
 await stage();mkdirSync(resolve(root,'previews'),{recursive:true});
 const unitSpan=Math.max(...manifest.models.filter(m=>!m.id.includes('formation')).map(m=>Math.hypot(...m.maximum.map((v,i)=>v-m.minimum[i]))))*1.15;
 for(const m of manifest.models){
  const span=m.id.includes('formation')?Math.hypot(...m.maximum.map((v,i)=>v-m.minimum[i]))*1.15:unitSpan;
  m.metres_per_pixel=span/512;
  const out=await page.evaluate(async m=>{
   renderer.load(await(await fetch(m.native)).arrayBuffer());const result={};
   for(const v of ['top','bottom','left','right','front','back','isometric']){
    renderer.render(v,{width:512,height:512,metresPerPixel:m.metres_per_pixel});result[v]=renderer.png();
   }
   renderer.render('isometric',{width:1300,height:750});result.hero=renderer.png();
   renderer.render('front',{width:750,height:750});result['detail-front']=renderer.png();
   if(m.id.includes('formation'))for(const v of ['left','right','top','bottom']){
    renderer.render(v,{width:1800,height:230,metresPerPixel:0.17});result['detail-'+v]=renderer.png();
   }
   return result;
  },m);
  m.view_metrics={};for(const [v,url] of Object.entries(out)){
   const file=m.views[v]||'previews/'+m.id+'-'+v+'.png',b=Buffer.from(url.split(',')[1],'base64');mkdirSync(dirname(resolve(root,file)),{recursive:true});writeFileSync(resolve(root,file),b);
   if(m.views[v])m.view_metrics[v]={width:512,height:512,sha256:sha(b)};
  }
 }
 const css='<style>body{font:18px system-ui;color:#262c57;background:#eceef6;margin:24px}h1{font-size:28px}.row{display:flex;gap:12px}.row>div{background:white;border-radius:12px;padding:10px;flex:1;min-width:0;text-align:center}img{width:100%;object-fit:contain}p{margin:6px}</style>';
 async function sheet(name,title,body){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+css+'<h1>'+title+'</h1>'+body);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name+'.png'),fullPage:true});}
 const near=manifest.models.filter(m=>m.family==='emu3000'&&m.category==='section');
 await sheet('overview','EMU3000｜白車身・炭黑罩面・細綠松肩線｜實際原生模型','<div class="row"><div><img src="previews/emu3000-ed-hero.png"></div></div><div class="row"><div><img src="previews/emu3000-ed-detail-front.png"><p>短斜鼻、黑罩、白下巴</p></div><div><img src="previews/emu3000-ep3-hero.png"><p>EP3 集電弓車</p></div></div><div class="row"><div><img src="previews/emu3000-formation-detail-left.png"><p>12 節；集電弓在 3 / 7 / 10 車</p></div></div>');
 await sheet('units','EMU3000｜8 種獨立單元（立體各自取景）',[near.slice(0,4),near.slice(4)].map(row=>'<div class="row">'+row.map(m=>'<div><img src="previews/'+m.id+'-hero.png"><p>'+m.id+' · '+m.triangles+' 三角</p></div>').join('')+'</div>').join(''));
 await sheet('formation','EMU3000｜完整編組，各列相同公尺尺度',['left','right','top','bottom'].map(v=>'<div class="row"><div><img src="previews/emu3000-formation-detail-'+v+'.png"><p>'+v+'</p></div></div>').join(''));
 await sheet('seven-directions','EMU3000｜各單元七向透明圖（每格同公尺尺度）',near.map(m=>'<h2>'+m.id+'</h2><div class="row">'+manifest.directions.map(v=>'<div><img src="'+m.views[v]+'"><p>'+v+'</p></div>').join('')+'</div>').join(''));
 async function match(ids,label){
  await stage();const ms=ids.map(id=>manifest.models.find(m=>m.id===id)||(id==='first-pass-ed'?{id,native:'history/first-pass/models/emu3000-ed.m3dmodel'}:id==='previous-ed'?{id,native:'history/3ab84550/models/emu3000-ed.m3dmodel'}:null));
  const out=await page.evaluate(async ms=>{
   const buffers=await Promise.all(ms.map(async m=>(await fetch(m.native)).arrayBuffer())),bounds=buffers.map(b=>{renderer.load(b);return renderer.bounds;});
   const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i]))),centre=low.map((n,i)=>(n+high[i])/2),extent=low.map((n,i)=>(high[i]-n)/2),out={};
   for(let i=0;i<buffers.length;i++){renderer.load(buffers[i]);renderer.centre=centre;renderer.extent=extent;for(const view of ['left','front','top','isometric']){renderer.render(view,{width:1000,height:500});out[i+'-'+view]=renderer.png();}}
   return {images:out,centre,extent};
  },ms);
  for(const [v,url] of Object.entries(out.images))writeFileSync(resolve(root,'previews',label+'-'+v+'.png'),Buffer.from(url.split(',')[1],'base64'));
  writeFileSync(resolve(root,label+'-camera.json'),JSON.stringify({ids,centre:out.centre,extent:out.extent,width:1000,height:500},null,2));
  await sheet(label,label+'｜同相機、同公尺尺度（原生幾何）',['left','front','top','isometric'].map(v=>'<h2>'+v+'</h2><div class="row">'+ms.map((m,i)=>'<div><img src="previews/'+label+'-'+i+'-'+v+'.png"><p>'+m.id+'</p></div>').join('')+'</div>').join(''));
 }
 if(existsSync(resolve(root,'history/3ab84550/models/emu3000-ed.m3dmodel')))await match(['previous-ed','emu3000-ed'],'revision-1-vs-2');
 await match(['before-set-emu3000-head','emu3000-ed'],'before-after');
 if(existsSync(resolve(root,'history/first-pass/models/emu3000-ed.m3dmodel')))await match(['first-pass-ed','emu3000-ed'],'first-pass-vs-final');
 await match(['before-formation','emu3000-formation'],'formation-before-after');
 await match(['refresh-700t-cab','refresh-e200','emu3000-ed'],'style-comparison');
 if(errors.length)throw Error(errors.join('\n'));
 manifest.render_verification={backend:'Chromium WebGL2 exact native geometry',views:manifest.models.length*7,transparent:true,scale:'all units share metres/pixel; each formation seven directions share metres/pixel; comparison cameras saved'};
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');console.log('Rendered '+manifest.models.length*7+' seven-way PNGs and fixed-camera comparisons.');
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
