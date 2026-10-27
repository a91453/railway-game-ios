import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)('playwright');
const source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex');
copyFileSync(resolve(source,'../station-kit/renderer.js'),resolve(root,'renderer.js'));
copyFileSync(resolve(source,'viewer.html'),resolve(root,'index.html'));
writeFileSync(resolve(root,'_render.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const address='http://127.0.0.1:'+server.address().port;
let browser;
try {
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1300,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);mkdirSync(resolve(root,'previews'),{recursive:true});
 for(const model of manifest.models){
  const results=await page.evaluate(async m=>{
   renderer.load(await(await fetch(m.native)).arrayBuffer());const out={};
   for(const view of ['top','bottom','left','right','front','back','isometric']){
    renderer.render(view,{width:512,height:512});const g=renderer.gl,p=new Uint8Array(512*512*4);g.readPixels(0,0,512,512,g.RGBA,g.UNSIGNED_BYTE,p);
    let n=0,l=512,t=512,r=0,b=0;
    for(let y=0;y<512;y++)for(let x=0;x<512;x++)if(p[(y*512+x)*4+3]>16){n++;l=Math.min(l,x);t=Math.min(t,511-y);r=Math.max(r,x);b=Math.max(b,511-y);}
    if(n<30||l<2||t<2||r>509||b>509)throw Error('Empty/clipped '+m.id+' '+view);
    out[view]={url:renderer.png(),opaque_pixels:n,bounds:[l,t,r+1,b+1]};
   }
   renderer.render('isometric',{width:1200,height:720});out.hero={url:renderer.png()};
   return out;
  },model);
  model.view_metrics={};for(const [view,result] of Object.entries(results)){
   const file=view==='hero'?'previews/'+model.id+'-hero.png':model.views[view];mkdirSync(dirname(resolve(root,file)),{recursive:true});
   const png=Buffer.from(result.url.split(',')[1],'base64');writeFileSync(resolve(root,file),png);
   if(view!=='hero')model.view_metrics[view]={width:512,height:512,opaque_pixels:result.opaque_pixels,visible_bounds:result.bounds,sha256:sha(png)};
  }
 }
 if(errors.length)throw Error(errors.join('\n'));
 manifest.render_verification={backend:'Chromium WebGL2, exact native vertices',views:manifest.models.length*manifest.directions.length,transparent:true,nonempty:true,unclipped:true};
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 const all=manifest.models.find(m=>m.category==='formation'),html='<style>body{font:18px system-ui;color:#262c57;background:#eceef6;margin:24px}h1{font-size:28px}.row{display:flex;gap:12px}.row>div{background:white;border-radius:12px;padding:10px;flex:1;min-width:0;text-align:center}img{width:100%;object-fit:contain}</style>';
 async function sheet(name,body){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+html+body);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name),fullPage:true});}
 const cab=manifest.models.find(m=>m.id==='emu500-emc');
 const details=await page.evaluate(async native=>{
  renderer.load(await(await fetch(native)).arrayBuffer());renderer.centre=[9.2,0,2.0];renderer.extent=[2.2,1.65,2.1];
  const out={};for(const view of ['isometric','left']){renderer.render(view,{width:1200,height:720});out[view]=renderer.png();}return out;
 },cab.native);
 for(const [view,data] of Object.entries(details))writeFileSync(resolve(root,'previews/cab-detail-'+view+'.png'),Buffer.from(data.split(',')[1],'base64'));
 const passengerDetail=await page.evaluate(async native=>{
  renderer.load(await(await fetch(native)).arrayBuffer());renderer.centre=[0,0,1.85];renderer.extent=[10.0,1.55,2.0];
  renderer.render('left',{width:1200,height:420});return renderer.png();
 },cab.native);
 writeFileSync(resolve(root,'previews/passenger-detail-left.png'),Buffer.from(passengerDetail.split(',')[1],'base64'));
 await sheet('overview.png','<h1>EMU500｜車頭、分格側窗與輪組</h1><div class="row"><div><img src="previews/cab-detail-isometric.png"><p>EMC 車頭｜近看</p></div><div><img src="'+cab.views.front+'"><p>正面</p></div></div><div class="row"><div><img src="previews/passenger-detail-left.png"><p>側窗與輪組｜近看</p></div></div><div class="row"><div><img src="previews/cab-detail-left.png"><p>鼻端側面｜近看</p></div><div><img src="'+cab.views.left+'"><p>端車全側面</p></div></div><div class="row"><div><img src="'+cab.views.top+'"><p>俯視</p></div><div><img src="previews/'+all.id+'-hero.png"><p>四節完整編組</p></div></div>');
 await sheet('directions.png','<h1>同一組模型的七向透明圖</h1><div class="row">'+manifest.directions.map(v=>'<div><img src="'+all.views[v]+'"><p>'+v+'</p></div>').join('')+'</div>');
 await sheet('units.png','<h1>獨立單元｜前端・後端</h1><div class="row">'+manifest.models.filter(m=>m.category==='section').map(m=>'<div><img src="previews/'+m.id+'-hero.png"><p>'+m.id+' · '+m.triangles+' 三角形</p></div>').join('')+'</div>');
 const comparison=manifest.models.find(m=>m.category==='comparison');
 const newUnit=manifest.models.find(m=>m.id==='emu500-emc');
 const matched=await page.evaluate(async paths=>{
  const a=await(await fetch(paths[0])).arrayBuffer(),b=await(await fetch(paths[1])).arrayBuffer();
  renderer.load(a);const centre=[...renderer.centre],extent=[...renderer.extent],out=[];
  for(const data of [a,b]){renderer.load(data);renderer.centre=centre;renderer.extent=extent;renderer.render('isometric',{width:900,height:600});out.push(renderer.png());}
  return out;
 },[newUnit.native,comparison.native]);
 for(const [i,data] of matched.entries())writeFileSync(resolve(root,'previews',i?'scale-existing.png':'scale-new.png'),Buffer.from(data.split(',')[1],'base64'));
 await sheet('style-comparison.png','<h1>EMU500／TEMU1000 風格｜同公尺尺度、同鏡頭</h1><div class="row"><div><img src="previews/scale-new.png"><p>EMU500 前端單元 · '+(newUnit.maximum[0]-newUnit.minimum[0]).toFixed(2)+' m</p></div><div><img src="previews/scale-existing.png"><p>TEMU1000 前端單元 · '+(comparison.maximum[0]-comparison.minimum[0]).toFixed(2)+' m</p></div></div><p>以前端單元的相機中心與範圍固定兩者，模型沒有個別放大。此圖只比較霧面材質、配色和細節密度，不作幾何來源。</p>');
 console.log('Rendered '+manifest.render_verification.views+' seven-direction PNGs and a real-metre fixed-camera style comparison.');
} finally {if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
