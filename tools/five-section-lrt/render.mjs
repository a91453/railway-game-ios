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
// This batch adds an explicit metre/pixel option without changing the shared renderer.
const rendererPath=resolve(root,'renderer.js');writeFileSync(rendererPath,readFileSync(rendererPath,'utf8').replace('zoom=1,vector}={}', 'zoom=1,vector,metresPerPixel}={}').replace('const radius=Math.max(', 'const radius=metresPerPixel ? height*metresPerPixel/2/zoom : Math.max('));
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
 const sectionSpan=Math.max(...manifest.models.filter(m=>m.category==='section').map(m=>Math.hypot(...m.maximum.map((v,i)=>v-m.minimum[i]))))*1.14;
 for(const model of manifest.models){
  model.metres_per_pixel=(model.category==='section'?sectionSpan:Math.hypot(...model.maximum.map((v,i)=>v-model.minimum[i]))*1.14)/512;
  const results=await page.evaluate(async m=>{
   renderer.load(await(await fetch(m.native)).arrayBuffer());const out={};
   for(const view of ['top','bottom','left','right','front','back','isometric']){
    renderer.render(view,{width:512,height:512,metresPerPixel:m.metres_per_pixel});const g=renderer.gl,p=new Uint8Array(512*512*4);g.readPixels(0,0,512,512,g.RGBA,g.UNSIGNED_BYTE,p);
    let n=0,l=512,t=512,r=0,b=0;
    for(let y=0;y<512;y++)for(let x=0;x<512;x++)if(p[(y*512+x)*4+3]>16){n++;l=Math.min(l,x);t=Math.min(t,511-y);r=Math.max(r,x);b=Math.max(b,511-y);}
    if(n<30||l<2||t<2||r>509||b>509)throw Error('Empty/clipped '+m.id+' '+view);
    out[view]={url:renderer.png(),opaque_pixels:n,bounds:[l,t,r+1,b+1]};
   }
   renderer.render('isometric',{width:1200,height:720});out.hero={url:renderer.png()};
   renderer.render('front',{width:700,height:700});out['detail-front']={url:renderer.png()};
   if(m.category==='formation')for(const view of ['left','right','top','bottom']){renderer.render(view,{width:1800,height:240,metresPerPixel:0.030});out['detail-'+view]={url:renderer.png()};}

   return out;
  },model);
  model.view_metrics={};for(const [view,result] of Object.entries(results)){
   const extra=view==='hero'||view.startsWith('detail-');const file=extra?'previews/'+model.id+'-'+view+'.png':model.views[view];mkdirSync(dirname(resolve(root,file)),{recursive:true});
   const png=Buffer.from(result.url.split(',')[1],'base64');writeFileSync(resolve(root,file),png);
   if(!extra)model.view_metrics[view]={width:512,height:512,opaque_pixels:result.opaque_pixels,visible_bounds:result.bounds,sha256:sha(png)};
  }
 }
 if(errors.length)throw Error(errors.join('\n'));
 manifest.render_verification={backend:'Chromium WebGL2, exact native vertices',views:56,transparent:true,nonempty:true,unclipped:true,scale:'same metres/pixel for all seven views of each model; all five units share one scale'};
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 const all=manifest.models.find(m=>m.category==='formation'),html='<style>body{font:18px system-ui;color:#262c57;background:#eceef6;margin:24px}h1{font-size:28px}.row{display:flex;gap:12px}.row>div{background:white;border-radius:12px;padding:10px;flex:1;min-width:0;text-align:center}img{width:100%;object-fit:contain}</style>';
 async function sheet(name,body){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+html+body);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name),fullPage:true});}
 await sheet('overview.png','<h1>五節鉸接低地板輕軌｜原生組合預覽</h1><div class="row"><div><img src="previews/'+all.id+'-hero.png"></div></div><div class="row">'+['left','front','right','top'].map(v=>'<div><img src="'+(v==='front'?'previews/lrt-five-leading-detail-front.png':all.views[v])+'"><p>'+v+(v==='front'?' · 局部放大':'')+'</p></div>').join('')+'</div>');
 await sheet('audit.png','<h1>完整編組｜正交檢查 · 各列 0.030 m / pixel</h1>'+['left','right','top','bottom'].map(v=>'<div style="background:white;border-radius:12px;margin:12px 0"><img style="width:100%" src="previews/'+all.id+'-detail-'+v+'.png"><p>'+v+'</p></div>').join(''));
 await sheet('directions.png','<h1>同一組模型的七向透明圖｜一致公尺尺度</h1><div class="row">'+manifest.directions.map(v=>'<div><img src="'+all.views[v]+'"><p>'+v+'</p></div>').join('')+'</div><p>七張原圖皆 '+all.metres_per_pixel.toFixed(4)+' m / pixel。駕駛端放大另見 overview 與 detail-front。</p>');
 await sheet('units.png','<h1>五個獨立單元｜長・短・長・短・長</h1><div class="row">'+manifest.models.filter(m=>m.category==='section').map(m=>'<div><img src="previews/'+m.id+'-hero.png"><p>'+m.id+' · '+m.triangles+' 三角形</p></div>').join('')+'</div>');
 const comparison=manifest.models.find(m=>m.id==='green-commuter-leading');
 const newUnit=manifest.models.find(m=>m.id==='lrt-five-leading');
 const matched=await page.evaluate(async paths=>{
  const a=await(await fetch(paths[0])).arrayBuffer(),b=await(await fetch(paths[1])).arrayBuffer();
  renderer.load(a);const low=[...renderer.bounds.low],high=[...renderer.bounds.high];renderer.load(b);for(let i=0;i<3;i++){low[i]=Math.min(low[i],renderer.bounds.low[i]);high[i]=Math.max(high[i],renderer.bounds.high[i]);}const centre=low.map((v,i)=>(v+high[i])/2),extent=low.map((v,i)=>(high[i]-v)/2),out=[];
  for(const data of [a,b]){renderer.load(data);renderer.centre=centre;renderer.extent=extent;renderer.render('isometric',{width:900,height:600});out.push(renderer.png());}
  return out;
 },[newUnit.native,comparison.native]);
 for(const [i,data] of matched.entries())writeFileSync(resolve(root,'previews',i?'scale-existing.png':'scale-new.png'),Buffer.from(data.split(',')[1],'base64'));
 await sheet('style-comparison.png','<h1>專案通勤車風格｜同公尺尺度、同鏡頭</h1><div class="row"><div><img src="previews/scale-new.png"><p>本次前端單元 · '+(newUnit.maximum[0]-newUnit.minimum[0]).toFixed(2)+' m</p></div><div><img src="previews/scale-existing.png"><p>既有通勤車單元 · '+(comparison.maximum[0]-comparison.minimum[0]).toFixed(2)+' m</p></div></div><p>以兩車外廓聯集的相機中心與範圍固定兩者，模型沒有個別放大。</p>');
 console.log('Rendered 56 seven-direction PNGs and a real-metre fixed-camera style comparison.');
} finally {if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
