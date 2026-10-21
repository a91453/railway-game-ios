import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync} from 'node:fs';
import {resolve,extname,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)('playwright');
const source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]||'docs/art/generated-2026-10-21-scene-kit/native3d');
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
copyFileSync(resolve(source,'renderer.js'),resolve(root,'renderer.js'));copyFileSync(resolve(source,'viewer.html'),resolve(root,'index.html'));
writeFileSync(resolve(root,'_render.html'),'<!doctype html><canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png','.glb':'model/gltf-binary'};
const server=createServer((request,response)=>{try{const name=decodeURIComponent(new URL(request.url,'http://localhost').pathname),path=resolve(root,'.'+name);if(!path.startsWith(root+'/'))throw Error('Outside root');const data=readFileSync(path);response.setHeader('Content-Type',mime[extname(path)]||'application/octet-stream');response.end(data);}catch{response.writeHead(404);response.end('Not found');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const address='http://127.0.0.1:'+server.address().port;
let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1200,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);
 for(const [index,model] of manifest.models.entries()){
  const images=await page.evaluate(async record=>{
   const response=await fetch(record.native);if(!response.ok)throw Error('Cannot read '+record.native);renderer.load(await response.arrayBuffer());
   const images={};for(const view of ['top','bottom','left','right','front','back','isometric']){
    renderer.render(view,{width:384,height:384});
    const gl=renderer.gl,pixels=new Uint8Array(384*384*4);gl.readPixels(0,0,384,384,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
    let count=0,left=384,top=384,right=0,bottom=0;
    for(let y=0;y<384;y++)for(let x=0;x<384;x++)if(pixels[(y*384+x)*4+3]>16){count++;left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,383-y);bottom=Math.max(bottom,383-y);}
    if(count<20)throw Error('Empty '+record.id+' '+view);
    if(left<2||top<2||right>381||bottom>381)throw Error('Clipped '+record.id+' '+view);
    images[view]={url:renderer.png(),opaque_pixels:count,visible_bounds:[left,top,right+1,bottom+1]};
   }return images;
  },model);
  model.view_metrics={};
  for(const [view,data] of Object.entries(images)){
   const file=resolve(root,model.views[view]);mkdirSync(dirname(file),{recursive:true});const png=Buffer.from(data.url.split(',')[1],'base64');writeFileSync(file,png);
   model.view_metrics[view]={width:384,height:384,opaque_pixels:data.opaque_pixels,visible_bounds:data.visible_bounds,sha256:createHash('sha256').update(png).digest('hex')};
  }
  if(index%20===0||index===manifest.models.length-1)console.log('Rendered '+(index+1)+'/'+manifest.models.length+' models, seven directions each.');
 }
 manifest.render_verification={backend:'Chromium WebGL 2 from native model vertices',models:manifest.models.length,views:manifest.models.length*7,size:[384,384],transparent:true,nonempty:true,unclipped:true,javascript_errors:errors};
 if(errors.length)throw Error(errors.join('\n'));
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 // Native 3D screenshots: these show vertices rendered above, not edited PNGs.
 mkdirSync(resolve(root,'previews'),{recursive:true});
 const cards=manifest.models.map(a=>'<article><img src="'+a.views.isometric+'"><div>'+a.name+'</div></article>').join('');
 await page.setContent('<html><head><meta charset="utf-8"><base href="'+address+'/"><style>body{font:13px system-ui;color:#262c57;background:#eceef6;margin:16px}main{display:grid;grid-template-columns:repeat(8,1fr);gap:8px}article{border-radius:9px;background:white;padding:6px;min-width:0}img{width:100%;aspect-ratio:1;object-fit:contain}</style></head><body><h1>原生 3D｜'+manifest.models.length+' 個模型</h1><main>'+cards+'</main></body></html>');
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews/overview.png'),fullPage:true});
 const examples=manifest.models.filter((a,i)=>i===0||a.variant===0),labels={top:'上視',bottom:'下視',left:'左視',right:'右視',front:'前視',back:'後視',isometric:'立體'};
 const rows=examples.map(a=>'<section><h3>'+a.name+'</h3><div class="row">'+Object.entries(a.views).map(([v,p])=>'<div><img src="'+p+'"><p>'+labels[v]+'</p></div>').join('')+'</div></section>').join('');
 await page.setContent('<html><head><meta charset="utf-8"><base href="'+address+'/"><style>body{font:13px system-ui;color:#262c57;background:#eceef6;margin:16px}section{border-radius:9px;background:white;padding:8px;margin-bottom:10px}.row{display:grid;grid-template-columns:repeat(7,1fr)}img{width:100%;aspect-ratio:1;object-fit:contain}p{margin:0;text-align:center}h3{margin:0}</style></head><body><h1>同一模型｜上下左右前後與立體視角</h1>'+rows+'</body></html>');
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews/directions.png'),fullPage:true});
 console.log('VERIFIED: '+manifest.render_verification.views+' transparent PNG renders, all nonempty and unclipped.');
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
