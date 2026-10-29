// Shared native renderer, fixed metre frames for BOTH fleets and LODs.
// node review.mjs ROOT OUTPUT [BASELINE_EXPORT]
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';import {createServer} from 'node:http';import {createRequire} from 'node:module';
const [root,out,baseline]=process.argv.slice(2).map(v=>resolve(v));mkdirSync(out,{recursive:true});
writeFileSync(out+'/renderer.js',readFileSync(new URL('../train-models/renderer.js',import.meta.url),'utf8').replace('../emu900-native/scene.js','./scene.js'));
writeFileSync(out+'/scene.js',readFileSync(new URL('../emu900-native/scene.js',import.meta.url)));
writeFileSync(out+'/index.html','<canvas id="c"></canvas><script type="module">import {NativeRenderer} from "./renderer.js";window.make=l=>{window.r=new NativeRenderer(document.getElementById("c"),l)};window.ready=true;</script>');
const server=createServer((q,s)=>{try{const path=new URL(q.url,'http://local').pathname;let file;
if(path.startsWith('/native/'))file=resolve(root,'.'+path.slice(7));else if(path.startsWith('/base/'))file=resolve(baseline,'.'+path.slice(5));else file=resolve(out,'.'+path);
s.setHeader('Content-Type',path.endsWith('.js')?'text/javascript':path.endsWith('.html')?'text/html':'application/octet-stream');s.end(readFileSync(file));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');await page.waitForFunction(()=>window.ready);
const manifests=['caf','citadis'].map(fleet=>({fleet,...JSON.parse(readFileSync(root+'/'+fleet+'/manifest.json'))}));await page.evaluate(l=>window.make(l),manifests[0].lighting);let count=0;
const frames={unit:{low:[-4.50,-1.40,0],high:[4.50,1.40,3.65]},formation:{low:[-17.083,-1.45,0],high:[17.083,1.45,4.55]}};
for(const mf of manifests)for(const model of mf.models)for(const material of ['color','clay','silhouette'])for(const view of ['front','left','right','top','isometric']){
 const frame=frames[model.native_kind==='assembly'?'formation':'unit'];
 const png=await page.evaluate(async({file,material,view,frame})=>{r.load(await(await fetch(file)).arrayBuffer(),material);r.centre=frame.low.map((v,i)=>(v+frame.high[i])/2);r.extent=frame.low.map((v,i)=>(frame.high[i]-v)/2);r.render(view,{width:1200,height:500,time:'day'});return r.png();},{file:'/native/'+mf.fleet+'/'+model.native,material,view,frame});
 writeFileSync(out+'/'+model.id+'-'+material+'-'+view+'.png',Buffer.from(png.split(',')[1],'base64'));count++;
}
if(baseline){const mf=JSON.parse(readFileSync(baseline+'/manifest.json'));for(const id of ['lrt-five-formation','green-tram-formation']){const model=mf.models.find(v=>v.id===id);if(!model)throw Error('missing real baseline '+id);for(const view of ['front','left','top','isometric']){const png=await page.evaluate(async({file,view,frame})=>{r.load(await(await fetch(file)).arrayBuffer(),'color');r.centre=frame.low.map((v,i)=>(v+frame.high[i])/2);r.extent=frame.low.map((v,i)=>(frame.high[i]-v)/2);r.render(view,{width:1200,height:500,time:'day'});return r.png();},{file:'/base/'+model.native,view,frame:frames.formation});writeFileSync(out+'/'+id+'-color-'+view+'.png',Buffer.from(png.split(',')[1],'base64'));count++;}}}
writeFileSync(out+'/frames.json',JSON.stringify({frames,projection:'shared orthographic frames, both fleets, all LODs; identical native game light; no per-model auto-fit',renders:count},null,2)+'\n');await browser.close();server.close();console.log('VERIFIED fixed-metre renders',count);
