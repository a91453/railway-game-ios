// Render original native vertices with one common metre camera and lighting.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const root=resolve(process.argv[2]);
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+new URL(q.url,'http://x').pathname);s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port+'/_r.html');await page.waitForFunction(()=>window.ready);
const manifest=JSON.parse(readFileSync(root+'/manifest.json'));await page.evaluate(l=>window.make(l),manifest.lighting);
mkdirSync(root+'/common',{recursive:true});
for(const m of manifest.models.filter(m=>m.id.includes('formation'))){
 for(const view of ['left','isometric']){
  const png=await page.evaluate(async({native,view})=>{r.load(await(await fetch(native)).arrayBuffer());r.centre=[0,0,1.98];r.extent=[51.155,1.55,1.98];r.render(view,{width:1400,height:300,time:'day'});return r.png();},{native:m.native,view});
  writeFileSync(root+'/common/'+m.id+'-'+view+'.png',Buffer.from(png.split(',')[1],'base64'));
 }
}
await browser.close();server.close();
