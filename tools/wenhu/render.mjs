// One fixed metre frame per unit/formation, shared across both fleets and LODs.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const root=resolve(process.argv[2]);
writeFileSync(root+'/renderer.js',readFileSync('tools/train-models/renderer.js','utf8').replace('../emu900-native/scene.js','./scene.js'));
copyFileSync('tools/emu900-native/scene.js',root+'/scene.js');
writeFileSync(root+'/_r.html','<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.make=l=>window.r=new NativeRenderer(document.getElementById("c"),l);window.ready=true;</script>');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+new URL(q.url,'http://x').pathname);s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/codex/cua_node/lib/node_modules/')('playwright');
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port+'/_r.html');await page.waitForFunction(()=>window.ready);
const manifest=JSON.parse(readFileSync(root+'/manifest.json'));await page.evaluate(l=>window.make(l),manifest.lighting);
for(const state of ['day','night','clay','silhouette']){
 mkdirSync(root+'/png/'+state,{recursive:true});
 for(const m of manifest.models){
  const data=readFileSync(resolve(root,m.native)).toString('base64');
  for(const view of ['front','back','left','right','top','bottom','isometric']){
   const png=await page.evaluate(({data,view,formation,state})=>{
    r.load(Uint8Array.from(atob(data),c=>c.charCodeAt(0)).buffer,state==='clay'||state==='silhouette'?state:'color');
    r.centre=[0,0,1.8];r.extent=[formation?27.56:6.90,1.4,1.8];
    r.render(view,{width:1200,height:420,time:state==='night'?'night':'day'});return r.png();
   },{data,view,formation:m.native_kind==='assembly',state});
   writeFileSync(root+'/png/'+state+'/'+m.id+'-'+view+'.png',Buffer.from(png.split(',')[1],'base64'));
  }
 }
}
await browser.close();server.close();console.log('Rendered 12 models, 7 directions, 4 states; fixed metre framing.');
