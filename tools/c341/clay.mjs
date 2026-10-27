import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]);
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',extname(p)==='.js'?'text/javascript':extname(p)==='.html'?'text/html':'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
writeFileSync(resolve(root,'_clay.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage(),base='http://127.0.0.1:'+server.address().port;await page.goto(base+'/_clay.html');await page.waitForFunction(()=>window.ready);
 const models=JSON.parse(readFileSync(resolve(root,'manifest.json'))).models.filter(m=>m.category==='formation'||m.id==='c341-dm');
 for(const model of models){
 const views=await page.evaluate(async path=>{
  const original=await(await fetch(path)).arrayBuffer(),result={};
  for(const [kind,color] of [['clay',0xffeaeaea],['silhouette',0xff111111]]){
   const copy=original.slice(0),d=new DataView(copy),count=d.getUint32(8,true),size=d.getUint32(12,true),start=16+Math.ceil(size/4)*4;
   for(let i=0;i<count;i++)for(let j=0;j<3;j++)d.setUint32(start+i*52+4+j*16+12,color,true);
   renderer.load(copy);
   for(const view of ['left','front','top','isometric']){renderer.render(view,{width:700,height:700});result[kind+'-'+view]=renderer.png();}
  }
  return result;
 },model.native);
 for(const [name,data] of Object.entries(views))writeFileSync(resolve(root,'previews',(model.category==='formation'?'':'cab-')+name+'.png'),Buffer.from(data.split(',')[1],'base64'));
 }
 console.log('Rendered cab and formation clay / silhouette views from the exact native triangles.');
}finally{if(browser)await browser.close();server.close();await import('node:fs').then(fs=>fs.unlinkSync(resolve(root,'_clay.html')));}
