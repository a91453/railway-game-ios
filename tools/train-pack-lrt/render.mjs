import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');
const root=resolve(process.argv[2]);
copyFileSync(new URL('../station-kit/renderer.js',import.meta.url).pathname,resolve(root,'renderer.js'));
writeFileSync(resolve(root,'_r.html'),'<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.r=new NativeRenderer(document.getElementById("c"));window.ready=true;</script>');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(q.url,'http://x').pathname));s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage({viewport:{width:1400,height:900}});await page.goto(base+'/_r.html');await page.waitForFunction(()=>window.ready);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));mkdirSync(resolve(root,'png'),{recursive:true});
for(const m of manifest.models){
 const shots=await page.evaluate(async m=>{r.load(await(await fetch(m.native)).arrayBuffer());const o={};
  const c0=r.centre.slice(),e0=r.extent.slice();
  if(m.id.endsWith('-curve')){r.render('top',{width:1400,height:700});o.top=r.png();r.render('isometric',{width:1400,height:700,vector:[0.3,-1,0.7]});o.iso=r.png();
   // the outer side of the first joint on the curve
   r.centre=[-18.7,0.6,1.7];r.extent=[3,3,2];r.render('x',{width:700,height:500,vector:[0.2,-1,0.35]});o.jointOut=r.png();
   r.centre=[-18.7,-0.6,1.7];r.render('x',{width:700,height:500,vector:[0.2,1,0.35]});o.jointIn=r.png();}
  else{r.render('left',{width:1800,height:260});o.side=r.png();r.render('isometric',{width:1400,height:520});o.iso=r.png();
   r.centre=[-18.7,0,1.7];r.extent=[3.5,3,2];r.render('x',{width:700,height:500,vector:[0.5,-1,0.45]});o.joint=r.png();
   r.centre=[-1.5,0,1.6];r.extent=[2.5,2,2];r.render('x',{width:600,height:500,vector:[1,-0.5,0.25]});o.nose=r.png();}
  r.centre=c0;r.extent=e0;return o;},m);
 for(const [k,v] of Object.entries(shots))writeFileSync(resolve(root,'png',m.id+'-'+k+'.png'),Buffer.from(v.split(',')[1],'base64'));
}
await browser.close();server.close();console.log('ok');
