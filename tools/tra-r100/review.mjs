// R100-specific common-metre camera. Geometry/lighting/rendering stay in the
// shared renderer; no independently reconstructed preview mesh.
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
 const imgs=await page.evaluate(async({row,lighting,mode})=>{const r=new R(document.querySelector('canvas'),lighting);r.load(await(await fetch(row.native)).arrayBuffer(),mode);
 // Identical camera for both liveries/LODs. Coach and assembly cameras
 // are explicit separate scales, never used as locomotive comparisons.
 const assembly=row.native_kind==='assembly';const coach=row.id.includes('coach');
 const length=assembly?Math.max(Math.abs(r.bounds.low[0]),Math.abs(r.bounds.high[0])):coach?10.5:8.1;
 r.extent=[length,1.6,2.05];r.centre=[0,0,2.05];const out={};for(const view of ['front','back','left','right','top','bottom','isometric']){r.render(view,{width:['front','back'].includes(view)?600:1200,height:420});out[view]=r.png();}return out;},{row,lighting:m.lighting,mode});
 const p=resolve(root,'review',mode);mkdirSync(p,{recursive:true});for(const[v,data]of Object.entries(imgs))writeFileSync(resolve(p,`${row.id}-${v}.png`),Buffer.from(data.split(',')[1],'base64'));
}
await browser.close();server.close();
