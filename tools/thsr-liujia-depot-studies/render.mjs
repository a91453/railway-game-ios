import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,unlinkSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const source=readFileSync(resolve('tools/depot-yard-kit/renderer.js'),'utf8').replace('count>100000','count>500000');
writeFileSync(resolve(root,'renderer.js'),source);
writeFileSync(resolve(root,'_render.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.r=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',extname(p)==='.js'?'text/javascript':extname(p)==='.html'?'text/html':'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(done=>server.listen(0,'127.0.0.1',done));
let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage(),address='http://127.0.0.1:'+server.address().port;
 await page.goto(address+'/_render.html');await page.waitForFunction(()=>window.ready);
 for(const record of manifest.models){
  const native=readFileSync(resolve(root,record.native));record.native_sha256=createHash('sha256').update(native).digest('hex');record.views={};
  const images=await page.evaluate(async rec=>{
   r.load(await(await fetch('/'+rec.native)).arrayBuffer());
   // Close views deliberately frame the maintenance hall; far views frame the entire yard.
   if(!rec.far){r.centre=[270,0,3];r.extent=[175,105,25];}
   const out={};for(const direction of ['top','bottom','left','right','front','back','isometric']){
    r.render(direction,{width:rec.far?900:900,height:650});out[direction]=r.png();
   }return out;
  },record);
  for(const [direction,data] of Object.entries(images)){
   const path=`views/${record.id}/${direction}.png`;mkdirSync(dirname(resolve(root,path)),{recursive:true});
   const bytes=Buffer.from(data.split(',')[1],'base64');writeFileSync(resolve(root,path),bytes);
   record.views[direction]=path;record.view_sha256??={};record.view_sha256[direction]=createHash('sha256').update(bytes).digest('hex');
  }
  console.log('Rendered',record.id);
 }
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_render.html'));}
