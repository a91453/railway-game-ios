// Compare two actual exported native cab units with identical camera bounds.
// The prior export is an input supplied at runtime and never enters the ZIP.
import {createServer} from 'node:http';
import {copyFileSync,readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const current=resolve(process.argv[2]),prior=resolve(process.argv[3]);
if(!prior)throw Error('Usage: node feedback-compare.mjs CURRENT_EXPORT PRIOR_EXPORT');
const model='models/emu500-emc.m3dmodel';
const before='_feedback-before.m3dmodel',after='_feedback-after.m3dmodel',html='_feedback.html';
copyFileSync(resolve(prior,model),resolve(current,before));
copyFileSync(resolve(current,model),resolve(current,after));
writeFileSync(resolve(current,html),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(current,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(current+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1400,height:900}}),base='http://127.0.0.1:'+server.address().port;
 await page.goto(base+'/'+html);await page.waitForFunction(()=>window.ready);
 const result=await page.evaluate(async paths=>{
  const buffers=await Promise.all(paths.map(async path=>(await fetch(path)).arrayBuffer()));
  const bounds=buffers.map(b=>{renderer.load(b);return renderer.bounds;});
  const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i])));
  const centre=low.map((n,i)=>(n+high[i])/2),extent=low.map((n,i)=>(high[i]-n)/2),out={};
  for(const [version,buffer] of [['before',buffers[0]],['after',buffers[1]]]){
   renderer.load(buffer);renderer.centre=centre;renderer.extent=extent;
   for(const view of ['left','front','isometric']){renderer.render(view,{width:900,height:600});out[version+'-'+view]=renderer.png();}
  }
  return {images:out,low,high};
 },['/'+before,'/'+after]);
 const entries=Object.entries(result.images);
 for(const [name,url] of entries)writeFileSync(resolve(current,'previews',name+'.png'),Buffer.from(url.split(',')[1],'base64'));
 const cards=['left','front','isometric'].map(view=>`<h2>${view}｜固定公尺尺度與相機</h2><div class="row"><div><img src="previews/before-${view}.png"><p>修正前</p></div><div><img src="previews/after-${view}.png"><p>修正後</p></div></div>`).join('');
 await page.setContent('<meta charset="utf-8"><base href="'+base+'/"/><style>body{font:19px system-ui;color:#26385c;background:#eceef6;margin:24px}h1{font-size:29px}.row{display:flex;gap:16px}.row>div{background:white;border-radius:12px;padding:12px;flex:1;text-align:center}img{width:100%}p{margin:5px}</style><h1>EMU500｜造型與遊戲配色修正前後</h1>'+cards+'<p>兩版使用相同原生模型座標、相機中心與範圍；截圖為 Chromium WebGL 2。</p>');
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
 await page.screenshot({path:resolve(current,'previews','before-after.png'),fullPage:true});
 console.log('Matched native-model before/after left, front and isometric views.');
}finally{if(browser)await browser.close();server.close();for(const p of [before,after,html])unlinkSync(resolve(current,p));}
