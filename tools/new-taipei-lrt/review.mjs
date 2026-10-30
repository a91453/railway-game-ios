// Fixed metre scale across both fleets and both LODs; local checks are not
// appearance acceptance. NativeRenderer consumes the final native/assembly.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const root=resolve(process.argv[2]);
const {chromium}=createRequire(process.env.NODE_GLOBAL)('playwright');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+new URL(q.url,'http://x').pathname);s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage();
for(const fleet of ['ankeng','danhai']){
 const dir=resolve(root,fleet),m=JSON.parse(readFileSync(resolve(dir,'manifest.json')));
 writeFileSync(resolve(dir,'renderer.js'),readFileSync(new URL('../train-models/renderer.js',import.meta.url),'utf8').replace('../emu900-native/scene.js','./scene.js'));
 copyFileSync(new URL('../emu900-native/scene.js',import.meta.url),resolve(dir,'scene.js'));
 writeFileSync(resolve(dir,'_review.html'),'<canvas id="c"></canvas><script type="module">import {NativeRenderer} from "./renderer.js";window.R=NativeRenderer;</script>');
 await page.goto(`http://127.0.0.1:${server.address().port}/${fleet}/_review.html`);await page.waitForFunction(()=>window.R);
 for(const row of m.models){
  const modes=row.native_kind==='assembly'?['color','clay','silhouette']:['color','clay','silhouette'];
  for(const mode of modes){
   const imgs=await page.evaluate(async({row,lighting,mode})=>{
    const r=new R(document.querySelector('canvas'),lighting);r.load(await(await fetch(row.native)).arrayBuffer(),mode);
    // Fixed field of view shared by both fleets: 40m x 12m for formations,
    // 10m x 5.2m for independent roles, front always 5.2m x 5.2m.
    const out={};for(const view of ['front','left','right','top','isometric']){
      const extent=row.native_kind==='assembly'?[17.225,1.325,2.18]:[4.5,1.325,2.18];
      r.extent=extent;r.centre=[0,0,2.18];
      r.render(view,{width:view==='front'?600:1200,height:view==='top'?300:600});out[view]=r.png();
    }return out;
   },{row,lighting:m.lighting,mode});
   const path=resolve(dir,'review',mode);mkdirSync(path,{recursive:true});
   for(const [v,data]of Object.entries(imgs))writeFileSync(resolve(path,`${row.id}-${v}.png`),Buffer.from(data.split(',')[1],'base64'));
  }
 }
}
await browser.close();server.close();console.log('VERIFIED fixed-metre native review render');
