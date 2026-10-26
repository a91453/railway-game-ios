// Decision 420: each subject's levels drawn with one camera (their joint
// bounds), three-quarter from the front and straight from the side; from
// tools/train-modeling-410/render.mjs.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');
const root=resolve(process.argv[2]);
writeFileSync(resolve(root,'renderer.js'),readFileSync(new URL('../station-kit/renderer.js',import.meta.url).pathname,'utf8').replace('count>15000','count>200000'));
writeFileSync(resolve(root,'_r.html'),'<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.r=new NativeRenderer(document.getElementById("c"));window.ready=true;</script>');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(q.url,'http://x').pathname));s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/opt/pw-browsers/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage({viewport:{width:1400,height:900}});await page.goto(base+'/_r.html');await page.waitForFunction(()=>window.ready);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));mkdirSync(resolve(root,'png'),{recursive:true});
for(const g of [...new Set(manifest.models.map(m=>m.group))]){
 const set=manifest.models.filter(m=>m.group===g);
 const shots=await page.evaluate(async set=>{
  const bounds=[];for(const m of set){r.load(await(await fetch(m.native)).arrayBuffer());bounds.push(r.bounds);}
  const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i])));
  const whole=()=>{r.centre=low.map((x,i)=>(x+high[i])/2);r.extent=low.map((x,i)=>(high[i]-x)/2);};
  const out={};
  for(const m of set){r.load(await(await fetch(m.native)).arrayBuffer());const o={};
   whole();r.render('x',{width:900,height:520,vector:[0.75,-1,0.4]});o.front=r.png();
   whole();r.render('left',{width:1600,height:300});o.side=r.png();
   out[m.id]=o;}
  return out;},set);
 for(const [id,o] of Object.entries(shots))for(const [k,v] of Object.entries(o))writeFileSync(resolve(root,'png',id+'-'+k+'.png'),Buffer.from(v.split(',')[1],'base64'));
}
await browser.close();server.close();console.log('ok');
