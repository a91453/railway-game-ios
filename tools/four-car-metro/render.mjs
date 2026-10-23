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
  model.metres_per_pixel=(model.category==='section'?sectionSpan:Math.max(...manifest.models.filter(m=>m.category==='formation').map(m=>Math.hypot(...m.maximum.map((v,i)=>v-m.minimum[i]))))*1.14)/512;
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
   if(m.category==='formation')for(const view of ['left','right','top','bottom']){renderer.render(view,{width:1800,height:240,metresPerPixel:0.035});out['detail-'+view]={url:renderer.png()};}

   return out;
  },model);
  model.view_metrics={};for(const [view,result] of Object.entries(results)){
   const extra=view==='hero'||view.startsWith('detail-');const file=extra?'previews/'+model.id+'-'+view+'.png':model.views[view];mkdirSync(dirname(resolve(root,file)),{recursive:true});
   const png=Buffer.from(result.url.split(',')[1],'base64');writeFileSync(resolve(root,file),png);
   if(!extra)model.view_metrics[view]={width:512,height:512,opaque_pixels:result.opaque_pixels,visible_bounds:result.bounds,sha256:sha(png)};
  }
 }
 if(errors.length)throw Error(errors.join('\n'));
 manifest.render_verification={backend:'Chromium WebGL2, exact native vertices',views:49,transparent:true,nonempty:true,unclipped:true,scale:'same metres/pixel for all seven views of each model; all four cars share one scale'};
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 const html='<style>body{font:18px system-ui;color:#262c57;background:#eceef6;margin:24px}h1{font-size:28px}.row{display:flex;gap:12px}.row>div{background:white;border-radius:12px;padding:10px;flex:1;min-width:0;text-align:center}img{width:100%;object-fit:contain}</style>';
 async function sheet(name,body){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+html+body);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name),fullPage:true});}
 for(const family of ['metro']){
  const train=manifest.models.find(m=>m.family===family&&m.category==='formation'),sections=manifest.models.filter(m=>m.family===family&&m.category==='section');
  const title='四節・暖白金砂';
  await sheet(family+'-overview.png','<h1>'+title+'｜實際原生模型</h1><div class="row"><div><img src="previews/'+train.id+'-hero.png"></div></div><div class="row"><div><img src="previews/'+sections[0].id+'-detail-front.png"><p>駕駛端局部放大</p></div><div><img src="'+train.views.left+'"><p>側面</p></div><div><img src="'+train.views.top+'"><p>上視</p></div></div>');
  await sheet(family+'-units.png','<h1>'+title+'｜獨立單元（立體各自取景）</h1><div class="row">'+sections.map(m=>'<div><img src="previews/'+m.id+'-hero.png"><p>'+m.id+' · '+m.triangles+' 三角</p></div>').join('')+'</div>');
  await sheet(family+'-audit.png','<h1>'+title+'｜正交各列 .035m/pixel</h1>'+['left','right','top','bottom'].map(v=>'<div style="background:white"><img src="previews/'+train.id+'-detail-'+v+'.png"><p>'+v+'</p></div>').join(''));
  await sheet(family+'-directions.png','<h1>'+title+'｜同公尺尺度七向透明圖</h1><div class="row">'+manifest.directions.map(v=>'<div><img src="'+train.views[v]+'"><p>'+v+'</p></div>').join('')+'</div>');
 }
 // Match camera and metre scale across both entire formations and legacy style.
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);
 const matched=await page.evaluate(async ms=>{
  const buffers=await Promise.all(ms.map(async m=>(await fetch(m.native)).arrayBuffer()));
  const bs=buffers.map(b=>{renderer.load(b);return renderer.bounds;});const low=[0,1,2].map(i=>Math.min(...bs.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bs.map(b=>b.high[i])));
  const centre=low.map((v,i)=>(v+high[i])/2),extent=low.map((v,i)=>(high[i]-v)/2);
  return buffers.map(b=>{renderer.load(b);renderer.centre=centre;renderer.extent=extent;renderer.render('isometric',{width:1400,height:470});return renderer.png();});
 },manifest.models.filter(m=>m.category==='formation'||m.category==='comparison'));
 for(const [i,data] of matched.entries())writeFileSync(resolve(root,'previews','scale-'+i+'.png'),Buffer.from(data.split(',')[1],'base64'));
 await sheet('overview.png','<h1>四節・暖白金砂都市列車｜實際原生模型</h1><div style="background:white;border-radius:12px"><img src="previews/scale-0.png"></div><div class="row"><div><img src="previews/metro-four-leading-detail-front.png"><p>近直立車頭、雙緩衝塊、中央連結器</p></div><div><img src="previews/metro-four-formation-detail-left.png"><p>四節等長、每側八組雙門、十六軸</p></div></div><p>新五張參考重建；尺寸為展示比例推估。靜態素材，暖白＋遊戲金砂色票。</p>');
 await sheet('style-comparison.png','<h1>新四節編組與既有都市車／七節輕軌單元｜相同相機、公尺尺度</h1>'+[0,1,2].map(i=>'<div style="background:white"><img src="previews/scale-'+i+'.png"><p>'+['新四節金砂編組','既有三節都市車的前單元','既有七節輕軌的前單元'][i]+'</p></div>').join(''));
 console.log('Rendered49 seven-way PNGs, orthographic sheets and fixed-camera fleet comparison.');
} finally {if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
