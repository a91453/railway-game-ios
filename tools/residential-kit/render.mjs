import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync,existsSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)('playwright'),source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]);
const shared=resolve(source,'../station-kit');
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const hash=b=>createHash('sha256').update(b).digest('hex'),rendererSHA=hash(readFileSync(resolve(shared,'renderer.js'))),cacheFile=resolve(root,'render-cache.json');
const cache=existsSync(cacheFile)?JSON.parse(readFileSync(cacheFile)):{};
copyFileSync(resolve(shared,'renderer.js'),resolve(root,'renderer.js'));copyFileSync(resolve(source,'viewer.html'),resolve(root,'index.html'));
const temporary=resolve(root,'_render.html');writeFileSync(temporary,'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'};
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',mime[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const address='http://127.0.0.1:'+server.address().port;
let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);
 for(const [i,record] of manifest.models.entries()){
  const cached=cache[record.id];
  if(cached?.native_sha256===record.native_sha256&&cached.renderer_sha256===rendererSHA&&manifest.directions.every(v=>{
   const p=resolve(root,record.views[v]);return existsSync(p)&&cached.view_metrics[v]&&hash(readFileSync(p))===cached.view_metrics[v].sha256;
  })){
   record.view_metrics=cached.view_metrics;
   if(i%100===0)console.log('Reused identical verified geometry / renderer / PNGs: '+(i+1)+'/'+manifest.models.length);
   continue;
  }
  const images=await page.evaluate(async record=>{
   const r=await fetch(record.native);if(!r.ok)throw Error(record.native);renderer.load(await r.arrayBuffer());const result={};
   for(const v of ['top','bottom','left','right','front','back','isometric']){
    renderer.render(v,{width:384,height:384});const g=renderer.gl,p=new Uint8Array(384*384*4);g.readPixels(0,0,384,384,g.RGBA,g.UNSIGNED_BYTE,p);
    let count=0,l=384,t=384,r=0,b=0;for(let y=0;y<384;y++)for(let x=0;x<384;x++)if(p[(y*384+x)*4+3]>16){count++;l=Math.min(l,x);t=Math.min(t,383-y);r=Math.max(r,x);b=Math.max(b,383-y);}
    if(count<20||l<2||t<2||r>381||b>381)throw Error('Empty or clipped '+record.id+' '+v);
    result[v]={url:renderer.png(),opaque_pixels:count,visible_bounds:[l,t,r+1,b+1]};
   }return result;
  },record);
  record.view_metrics={};for(const [v,data] of Object.entries(images)){const path=resolve(root,record.views[v]);mkdirSync(dirname(path),{recursive:true});const png=Buffer.from(data.url.split(',')[1],'base64');writeFileSync(path,png);record.view_metrics[v]={width:384,height:384,opaque_pixels:data.opaque_pixels,visible_bounds:data.visible_bounds,sha256:createHash('sha256').update(png).digest('hex')};}
  cache[record.id]={native_sha256:record.native_sha256,renderer_sha256:rendererSHA,view_metrics:record.view_metrics};
  if(i%25===0||i===manifest.models.length-1)console.log('Rendered '+(i+1)+'/'+manifest.models.length+' models in seven directions.');
 }
 if(errors.length)throw Error(errors.join('\n'));
 manifest.render_verification={backend:'Chromium WebGL 2; actual native geometry',renderer_sha256:rendererSHA,transparent:true,size:[384,384],views:manifest.models.length*7,nonempty:true,unclipped:true};
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 writeFileSync(cacheFile,JSON.stringify(cache)+'\n');
 mkdirSync(resolve(root,'previews'),{recursive:true});
 const css='<style>body{font:16px system-ui;color:#262c57;background:#eceef6;margin:16px}main{display:grid;gap:10px;grid-template-columns:repeat(6,1fr)}article,section{background:white;border-radius:9px;padding:8px;min-width:0}img{width:100%;aspect-ratio:1;object-fit:contain}h3{font-size:15px;margin:4px}section{margin:12px 0}.row{display:grid;grid-template-columns:repeat(7,1fr)}p{font-size:13px;text-align:center;margin:0}</style>';
 async function sheet(name,title,html){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+css+'<h1>'+title+'</h1>'+html);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name),fullPage:true});}
 const parts=manifest.models.filter(m=>m.category!=='example'),examples=manifest.models.filter(m=>m.category==='example');
 const cards=records=>'<main>'+records.map(m=>'<article><img src="'+m.views.isometric+'"><h3>'+m.name+'</h3></article>').join('')+'</main>';
 await sheet('parts.png','24 種台灣住宅街廓素材',cards(parts));
 await sheet('examples.png','四個原生組景｜實際模型組裝',cards(examples));
 const groups={home:'住宅',boundary:'界牆與出入口',yard:'庭院與街邊'};
 for(const [category,title] of Object.entries(groups))await sheet(category+'.png',title,cards(parts.filter(m=>m.category===category)));
 const picks=['narrowTownhouse','arcadeTownhouse','ironGate','balconyModule','waterTank','clothesline'].map(p=>parts.find(m=>m.id==='residential-'+p));
 await sheet('directions.png','上／下／左／右／前／後／立體｜同一個原生模型',picks.map(m=>'<section><h3>'+m.name+'</h3><div class="row">'+Object.entries(m.views).map(([v,p])=>'<div><img src="'+p+'"><p>'+v+'</p></div>').join('')+'</div></section>').join(''));
 const overview=[...examples,...parts];
 await sheet('overview.png','24 種重組素材 · 住宅／界牆／庭院 · 4 個組景',cards(overview));
 const under=[];for(const m of picks.concat(['carport','bikeShed'].map(p=>parts.find(m=>m.id==='residential-'+p)))){const png=await page.evaluate(async m=>{renderer.load(await(await fetch(m.native)).arrayBuffer());renderer.render('isometric',{width:384,height:384,vector:[1,-1,-0.45]});return renderer.png();},m);const path='previews/'+m.id+'-underside.png';writeFileSync(resolve(root,path),Buffer.from(png.split(',')[1],'base64'));under.push({...m,views:{isometric:path}});}
 await sheet('undersides.png','下斜視｜立柱、安裝面、屋簷與底面',cards(under));
 await sheet('style-checks.png','四底色、小尺寸、模糊與灰階',picks.filter(m=>!m.id.includes('Office')).slice(0,4).map(m=>'<section><h3>'+m.name+'</h3><div style="display:flex">'+['#fff','#262c57','#dce9da','#263c40'].map(c=>'<img style="width:23%;background:'+c+'" src="'+m.views.isometric+'">').join('')+'</div><p>'+[120,64,44,28].map(s=>'<img style="width:'+s+'px" src="'+m.views.isometric+'">').join('')+'<img style="width:120px;filter:blur(3px)" src="'+m.views.isometric+'"><img style="width:120px;filter:grayscale(1)" src="'+m.views.isometric+'"></p></section>').join(''));
 console.log('VERIFIED '+manifest.models.length*7+' nonempty, unclipped RGBA views; review sheets rendered.');
}finally{if(browser)await browser.close();server.close();unlinkSync(temporary);}
