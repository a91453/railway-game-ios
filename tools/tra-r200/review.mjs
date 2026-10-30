// Fixed metres, camera and lighting across both R200 LODs.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const root=resolve(process.argv[2]);
const {chromium}=createRequire(process.env.NODE_GLOBAL)('playwright');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+new URL(q.url,'http://x').pathname);s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage();const m=JSON.parse(readFileSync(resolve(root,'manifest.json')));
writeFileSync(resolve(root,'renderer.js'),readFileSync(new URL('../train-models/renderer.js',import.meta.url),'utf8').replace('../emu900-native/scene.js','./scene.js'));
copyFileSync(new URL('../emu900-native/scene.js',import.meta.url),resolve(root,'scene.js'));
writeFileSync(resolve(root,'_review.html'),'<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.R=NativeRenderer;</script>');
await page.goto(`http://127.0.0.1:${server.address().port}/_review.html`);await page.waitForFunction(()=>window.R);
for(const row of m.models)for(const mode of ['color','clay','silhouette']){
 const imgs=await page.evaluate(async({row,lighting,mode})=>{const r=new R(document.querySelector('canvas'),lighting);r.load(await(await fetch(row.native)).arrayBuffer(),mode);r.extent=[10.1,1.55,2.1];r.centre=[0,0,2.1];const out={};for(const view of ['front','back','left','right','top','bottom','isometric']){r.render(view,{width:['front','back'].includes(view)?600:1200,height:420});out[view]=r.png();}return out;},{row,lighting:m.lighting,mode});
 const p=resolve(root,'review',mode);mkdirSync(p,{recursive:true});for(const[v,data]of Object.entries(imgs))writeFileSync(resolve(p,`${row.id}-${v}.png`),Buffer.from(data.split(',')[1],'base64'));
}
await browser.close();server.close();
