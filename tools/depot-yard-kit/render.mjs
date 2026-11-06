import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync,statSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]),source=resolve('tools/station-kit/renderer.js');
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const hash=b=>createHash('sha256').update(b).digest('hex');
copyFileSync(source,resolve(root,'renderer.js'));
writeFileSync(resolve(root,'_render.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',extname(p)==='.js'?'text/javascript':extname(p)==='.html'?'text/html':'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(done=>server.listen(0,'127.0.0.1',done));
let browser;
try {
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage(),address='http://127.0.0.1:'+server.address().port;
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);
 for(const [index,record] of manifest.models.entries()) {
  const native=readFileSync(resolve(root,record.native));record.native_sha256=hash(native);
  record.views={};record.view_sha256={};
  const images=await page.evaluate(async record=>{renderer.load(await(await fetch('/'+record.native)).arrayBuffer());const result={};for(const direction of ['top','bottom','left','right','front','back','isometric']){renderer.render(direction,{width:384,height:384});result[direction]=renderer.png();}return result;},record);
  for(const [direction,data] of Object.entries(images)) {
   const path='views/'+record.id+'/'+direction+'.png',absolute=resolve(root,path),png=Buffer.from(data.split(',')[1],'base64');
   mkdirSync(dirname(absolute),{recursive:true});writeFileSync(absolute,png);
   if(statSync(absolute).size>2_000_000)throw Error('Oversized PNG '+path);
   record.views[direction]=path;record.view_sha256[direction]=hash(png);
  }
  if(index%25===0)console.log('Rendered '+(index+1)+'/'+manifest.models.length);
 }
 mkdirSync(resolve(root,'previews'),{recursive:true});
 for(const system of ['wenhu','taiwanRail']) {
  const record=manifest.models.find(model=>model.id==='depot-yard-scene-'+system);
  const data=await page.evaluate(async record=>{
   renderer.load(await(await fetch('/'+record.native)).arrayBuffer());
   renderer.render('isometric',{width:1024,height:1024});return renderer.png();
  },record);
  const path=resolve(root,'previews',system==='wenhu'?'wenhu-depot-yard.png':'taiwan-rail-depot-yard.png');
  writeFileSync(path,Buffer.from(data.split(',')[1],'base64'));
  if(statSync(path).size>2_000_000)throw Error('Oversized scene '+path);
 }
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 console.log('Rendered '+manifest.models.length*7+' transparent views');
} finally {if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
