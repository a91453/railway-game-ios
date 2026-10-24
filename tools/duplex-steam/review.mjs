// Before batch rendering, inspect the actual native cab and formation in colour,
// clay and silhouette. No concept drawing or substitute geometry is involved.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,copyFileSync,mkdirSync,unlinkSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]);
copyFileSync(resolve(source,'../station-kit/renderer.js'),resolve(root,'renderer.js'));
writeFileSync(resolve(root,'_review.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',extname(p)==='.js'?'text/javascript':extname(p)==='.png'?'image/png':'text/html');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try {
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1500,height:900}}),base='http://127.0.0.1:'+server.address().port;
 await page.goto(base+'/_review.html');await page.waitForFunction(()=>window.ready);mkdirSync(resolve(root,'previews'),{recursive:true});
 for(const id of ['duplex-locomotive','duplex-tender','duplex-formation']){
 const images=await page.evaluate(async id=>{
  const original=await(await fetch('models/'+id+'.m3dmodel')).arrayBuffer(),out={};
  for(const [kind,color] of [['colour',null],['clay',0xffeaeaea],['silhouette',0xff111111]]){
   const buffer=original.slice(0),d=new DataView(buffer),start=16+Math.ceil(d.getUint32(12,true)/4)*4;
   if(color!==null)for(let i=0;i<d.getUint32(8,true);i++)for(let j=0;j<3;j++)d.setUint32(start+i*52+4+j*16+12,color,true);
   renderer.load(buffer);
   for(const view of ['left','front','top','isometric']){renderer.render(view,{width:900,height:500});out[kind+'-'+view]=renderer.png();}
  }return out;
 },id);
 for(const [key,url]of Object.entries(images))writeFileSync(resolve(root,'previews',id+'-'+key+'.png'),Buffer.from(url.split(',')[1],'base64'));
 const rows=['colour','clay','silhouette'].map(kind=>'<div class="row">'+['left','front','top','isometric'].map(view=>'<div><img src="previews/'+id+'-'+kind+'-'+view+'.png"><p>'+kind+' · '+view+'</p></div>').join('')+'</div>').join('');
 await page.setContent('<meta charset="utf-8"><base href="'+base+'/"><style>body{font:18px system-ui;background:#eceef6;color:#262c57;margin:20px}.row{display:flex;gap:12px}.row>div{flex:1;background:white;min-width:0}img{width:100%}</style><h1>'+id+'｜實際原生模型初檢</h1>'+rows);
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',id+'-review.png'),fullPage:true});
 await page.goto(base+'/_review.html');await page.waitForFunction(()=>window.ready);
 }
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_review.html'));}
