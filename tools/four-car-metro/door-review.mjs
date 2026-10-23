// Compare real native revisions, proving all geometry outside the doors stable.
import{readFileSync,writeFileSync,copyFileSync,unlinkSync}from'node:fs';
import{resolve,extname}from'node:path';import{createServer}from'node:http';
import{createRequire}from'node:module';import{createHash}from'node:crypto';
import assert from'node:assert/strict';import{readNative}from'../station-kit/package.mjs';
const root=resolve(process.argv[2]),prior=resolve(process.argv[3]);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex');
function stable(vs){let keep=[];for(let i=0;i<vs.length;i+=3){const t=vs.slice(i,i+3),door=t.every(v=>Math.abs(Math.abs(v.position[0])-2.63)<.82&&Math.abs(v.position[1])>1.339&&v.position[2]>=.859&&v.position[2]<=3.131);if(!door)keep.push(t);}return keep;}
const records=[];
for(const m of manifest.models.filter(m=>m.category==='section')){
 const a=readFileSync(resolve(prior,m.native)),b=readFileSync(resolve(root,m.native));
 const old=readNative(a).vertices,now=readNative(b).vertices;
 assert.deepEqual(stable(now),stable(old),m.id+' changed outside door bounds');
 assert.notEqual(sha(a),sha(b),'Door revision missing');
 records.push({id:m.id,before_sha256:sha(a),after_sha256:sha(b),unchanged_non_door_triangles:stable(now).length});
}
copyFileSync(resolve(prior,'models/metro-four-leading.m3dmodel'),resolve(root,'_door-before.m3dmodel'));
writeFileSync(resolve(root,'_door.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+new URL(req.url,'http://localhost').pathname);if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 const{chromium}=createRequire(import.meta.url)('playwright');browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1400,height:900}}),base='http://127.0.0.1:'+server.address().port;await page.goto(base+'/_door.html');await page.waitForFunction(()=>window.ready);
 const result=await page.evaluate(async()=>{
  const buffers=await Promise.all(['_door-before.m3dmodel','models/metro-four-leading.m3dmodel'].map(async p=>(await fetch(p)).arrayBuffer()));const bounds=buffers.map(b=>{renderer.load(b);return renderer.bounds;});const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i]))),centre=low.map((v,i)=>(v+high[i])/2),extent=low.map((v,i)=>(high[i]-v)/2),images={};
  for(const[i,b]of buffers.entries())for(const view of ['left','isometric','door']){
   renderer.load(b);renderer.centre=centre;renderer.extent=extent;
   if(view==='door'){renderer.centre=[2.63,0,2.0];renderer.extent=[1.4,1.4,1.4];renderer.render('left',{width:640,height:700,metresPerPixel:.0045});}
   else renderer.render(view,{width:900,height:600});
   // The door detail deliberately crops the surrounding body; make its
   // white background opaque so it cannot be mistaken for an uncropped
   // seven-direction transparent asset.
   let png=renderer.png();
   if(view==='door'){const c=document.createElement('canvas');c.width=640;c.height=700;const context=c.getContext('2d');context.fillStyle='#fff';context.fillRect(0,0,640,700);context.drawImage(document.getElementById('canvas'),0,0);png=c.toDataURL('image/png');}
   images[(i?'after':'before')+'-'+view]=png;
  }return images;
 });
 for(const[n,data]of Object.entries(result))writeFileSync(resolve(root,'previews','doors-'+n+'.png'),Buffer.from(data.split(',')[1],'base64'));
 const html='<meta charset="utf-8"><base href="'+base+'/"><style>body{font:20px system-ui;color:#262c57;background:#eceef6;margin:24px}.row{display:flex;gap:16px}.row>div{flex:1;background:white;border-radius:12px;padding:12px;min-width:0}img{width:100%}h1{font-size:28px}</style><h1>門板修訂｜實際原生模型、同相機與同公尺尺度</h1>'+['door','left','isometric'].map(v=>'<h2>'+({door:'門局部：.0045m/pixel',left:'整車側面',isometric:'斜視'})[v]+'</h2><div class="row">'+['before','after'].map(n=>'<div><img src="previews/doors-'+n+'-'+v+'.png"><p>'+(n==='before'?'修訂前：深灰門板、窄窗':'修訂後：淺暖灰薄門框、寬玻璃、腰帶連續')+'</p></div>').join('')+'</div>').join('');
 await page.setContent(html);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews/doors-before-after.png'),fullPage:true});
 writeFileSync(resolve(root,'door-verification.json'),JSON.stringify({status:'VERIFIED',baseline_producer:'08e50f652d1ca768c85cec60ddb87bb21a640319',baseline_private_commit:'3246cad87e867223e60356d4400084832d97ba2a',scope:'Only door plates, door glass and waist-band continuation within each original door opening; all non-door native triangles exactly equal including colour / normals / order',camera:'identical before/after centre, extent and view; closeup .0045m/pixel',models:records},null,2)+'\n');
 console.log('VERIFIED four units unchanged outside doors; rendered fixed-camera before/after');
}finally{if(browser)await browser.close();server.close();for(const n of ['_door.html','_door-before.m3dmodel'])unlinkSync(resolve(root,n));}
