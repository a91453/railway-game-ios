import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync,existsSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {readNative} from '../station-kit/package.mjs';
const {chromium}=createRequire(import.meta.url)('playwright'),source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]);
const hash=b=>createHash('sha256').update(b).digest('hex'),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
copyFileSync(resolve(source,'../station-kit/renderer.js'),resolve(root,'renderer.js'));copyFileSync(resolve(source,'viewer.html'),resolve(root,'index.html'));
writeFileSync(resolve(root,'_render.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const address='http://127.0.0.1:'+server.address().port;let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1200,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);
 mkdirSync(resolve(root,'previews'),{recursive:true});
 for(const record of manifest.models){
  const result=await page.evaluate(async m=>{
   renderer.load(await(await fetch(m.native)).arrayBuffer());const result={};
   for(const v of ['top','bottom','left','right','front','back','isometric']){
    renderer.render(v,{width:384,height:384});const g=renderer.gl,p=new Uint8Array(384*384*4);g.readPixels(0,0,384,384,g.RGBA,g.UNSIGNED_BYTE,p);
    let count=0,l=384,t=384,r=0,b=0;for(let y=0;y<384;y++)for(let x=0;x<384;x++)if(p[(y*384+x)*4+3]>16){count++;l=Math.min(l,x);t=Math.min(t,383-y);r=Math.max(r,x);b=Math.max(b,383-y);}
    if(count<20||l<2||t<2||r>381||b>381)throw Error('Empty or clipped '+m.id+' '+v);
    result[v]={url:renderer.png(),opaque_pixels:count,visible_bounds:[l,t,r+1,b+1]};
   }
   renderer.render('isometric',{width:900,height:620});result.hero=renderer.png();
   renderer.render('isometric',{width:900,height:620,vector:[-1,1,0.6]});result.rear=renderer.png();
   renderer.render('isometric',{width:900,height:620,vector:[1,-1,-0.35]});result.underside=renderer.png();
   return result;
  },record);
  record.view_metrics={};for(const [v,data] of Object.entries(result)){
   if(['hero','rear','underside'].includes(v)){writeFileSync(resolve(root,'previews',record.id+'-'+v+'.png'),Buffer.from(data.split(',')[1],'base64'));continue;}
   const path=resolve(root,record.views[v]);mkdirSync(dirname(path),{recursive:true});const png=Buffer.from(data.url.split(',')[1],'base64');writeFileSync(path,png);record.view_metrics[v]={width:384,height:384,opaque_pixels:data.opaque_pixels,visible_bounds:data.visible_bounds,sha256:hash(png)};
  }
 }
 // Preview-only scene: actual exported vertices, translated sideways in
 // metres; a single camera preserves the relative length of all four buses.
 const fleetOrder=[manifest.models[1],manifest.models[2],manifest.models[0],manifest.models[3]],chunks=[];
 let fleetTriangles=0;
 for(const [i,m] of fleetOrder.entries()){
  const native=readFileSync(resolve(root,m.native)),parsed=readNative(native),start=16+Math.ceil(native.readUInt32LE(12)/4)*4,chunk=Buffer.from(native.subarray(start));
  if(chunk.length!==m.triangles*52)throw Error('Fleet source size');
  for(let t=0;t<m.triangles;t++)for(let v=0;v<3;v++){const at=t*52+4+v*16+4;chunk.writeFloatLE(chunk.readFloatLE(at)+i*4.8,at);}
  chunks.push(chunk);fleetTriangles+=parsed.vertices.length/3;
 }
 const header=Buffer.alloc(20);header.write('M3DM');header.writeUInt16LE(1,4);header.writeUInt32LE(fleetTriangles,8);header.writeUInt32LE(2,12);header.write('{}',16);
 const fleet=Buffer.concat([header,...chunks]),parsedFleet=readNative(fleet);
 if(parsedFleet.vertices.length!==fleetTriangles*3||!parsedFleet.vertices.every(v=>v.position.every(Number.isFinite)))throw Error('Invalid fleet preview');
 const fleetImage=await page.evaluate(base64=>{const bytes=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));renderer.load(bytes.buffer);renderer.render('isometric',{width:1200,height:900,vector:[1,-1,1.2]});return renderer.png();},fleet.toString('base64'));
 writeFileSync(resolve(root,'previews/fleet-native.png'),Buffer.from(fleetImage.split(',')[1],'base64'));
 manifest.fleet_preview={source_ids:fleetOrder.map(m=>m.id),translations_metres:fleetOrder.map((_,i)=>[0,i*4.8,0]),triangles:fleetTriangles,single_camera:true,model_count:0,sha256:hash(readFileSync(resolve(root,'previews/fleet-native.png')))};
 if(errors.length)throw Error(errors.join('\n'));
 manifest.render_verification={backend:'Chromium WebGL2 actual native vertices',renderer_sha256:hash(readFileSync(resolve(root,'renderer.js'))),views:28,transparent:true,nonempty:true,unclipped:true};
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 const bus=manifest.models[0],old=manifest.models[1],css='<style>body{font:18px system-ui;color:#262c57;background:#eceef6;margin:24px}h1{font-size:30px}h2{font-size:20px}main,.row{display:flex;gap:12px}section{background:white;border-radius:12px;padding:12px;flex:1;min-width:0}img{width:100%;object-fit:contain}p{margin:4px 0}.row section{text-align:center}.row img{aspect-ratio:1}.big{max-height:450px}</style>';
 async function sheet(name,html){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+css+html);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name),fullPage:true});}
 await sheet('overview.png','<h1>三軸高車身遊覽車｜暖白 × 暖紅</h1><main><section><h2>雙斜面風擋・右側前門與行李艙</h2><img class="big" src="previews/'+bus.id+'-hero.png"></section><section><h2>三軸輪組・高車身與分離尾燈</h2><img class="big" src="previews/'+bus.id+'-rear.png"></section></main><div class="row">'+['front','back','left','right'].map(v=>'<section><img src="'+bus.views[v]+'"><p>'+({front:'前視',back:'後視',left:'左視',right:'右視'})[v]+'</p></section>').join('')+'</div>');
 if(existsSync(resolve(root,'previews/luggage-before-hero.png')))await sheet('luggage-before-after.png','<h1>行李艙門修正｜車身同色・細接縫・小把手</h1><main><section><h2>修正前：厚灰框與突出蓋板</h2><img src="previews/luggage-before-hero.png"></section><section><h2>修正後：貼齊車身的同色艙門</h2><img src="previews/'+bus.id+'-hero.png"></section></main>');
 await sheet('directions.png','<h1>同一原生車型｜七向透明圖</h1><div class="row">'+Object.entries(bus.views).map(([v,p])=>'<section><img src="'+p+'"><p>'+v+'</p></section>').join('')+'</div>');
 await sheet('comparison.png','<h1>遊戲風格對照｜1款新遊覽車與3款已完成車型</h1><main>'+manifest.models.map(m=>'<section><h2>'+m.name+'</h2><img src="previews/'+m.id+'-hero.png"><p>長 '+(m.maximum[0]-m.minimum[0]).toFixed(2)+' m · '+m.triangles+' 三角形</p></section>').join('')+'</main>');
 await sheet('fleet.png','<h1>同尺度車隊｜小巴也已完成遊戲風格</h1><p>同一鏡頭與公尺比例，由近至遠：藍綠高頂小巴 → 白藍低地板 → 新暖紅三軸遊覽車 → 既有大型公車。</p><section><img src="previews/fleet-native.png"></section>');
 await sheet('style-checks.png','<h1>四底色・小尺寸・灰階與底面</h1><div class="row">'+['#fff','#262c57','#dce9da','#263c40'].map(c=>'<section style="background:'+c+'"><img src="'+bus.views.isometric+'"></section>').join('')+'</div><section>'+[120,64,44,28].map(s=>'<img style="width:'+s+'px" src="'+bus.views.isometric+'">').join('')+'<img style="width:120px;filter:blur(3px)" src="'+bus.views.isometric+'"><img style="width:120px;filter:grayscale(1)" src="'+bus.views.isometric+'"></section><main><section><img src="previews/'+bus.id+'-underside.png"></section><section><img src="previews/'+bus.id+'-rear.png"></section></main>');
 console.log('VERIFIED 28 seven-view PNGs, plus front/rear/underside and style review sheets.');
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
