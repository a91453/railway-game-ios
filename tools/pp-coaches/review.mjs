// Review only the actual final native vertices, independently for both LODs.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,unlinkSync} from 'node:fs';
import {resolve,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const source=dirname(fileURLToPath(import.meta.url)),root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
let renderer=readFileSync(resolve(source,'scene.js'),'utf8').replace('export function assemblyNative','function assemblyNative')+'\n'+readFileSync(resolve(source,'../station-kit/renderer.js'),'utf8').replace(' load(buffer){',' prepare(buffer){return assemblyNative(buffer);}\n load(buffer){buffer=assemblyNative(buffer);').replace('count>15000','count>200000');
renderer=renderer.replace('zoom=1,vector}={}','zoom=1,vector,metresPerPixel}={}').replace('const radius=Math.max(','const radius=metresPerPixel ? height*metresPerPixel/2/zoom : Math.max(');
writeFileSync(resolve(root,'renderer.js'),renderer);
writeFileSync(resolve(root,'_review.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',extname(p)==='.js'?'text/javascript':extname(p)==='.png'?'image/png':'text/html');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1700,height:900}}),base='http://127.0.0.1:'+server.address().port;
 async function stage(){await page.goto(base+'/_review.html');await page.waitForFunction(()=>window.ready);}
 await stage();mkdirSync(resolve(root,'previews'),{recursive:true});
 for(const m of manifest.models.filter(m=>m.category==='section')){
  const images=await page.evaluate(async m=>{
   const original=renderer.prepare(await(await fetch(m.native)).arrayBuffer()),out={};
   for(const [kind,color] of [['colour',null],['clay',0xffeaeaea],['silhouette',0xff111111]]){
    const buffer=original.slice(0),d=new DataView(buffer),start=16+Math.ceil(d.getUint32(12,true)/4)*4;
    if(color!==null)for(let i=0;i<d.getUint32(8,true);i++)for(let j=0;j<3;j++)d.setUint32(start+i*52+4+j*16+12,color,true);
    renderer.load(buffer);
    for(const view of ['left','front','top','isometric']){renderer.render(view,{width:1000,height:500});out[kind+'-'+view]=renderer.png();}
   }return out;
  },m);
  for(const [key,url]of Object.entries(images))writeFileSync(resolve(root,'previews',m.id+'-'+key+'.png'),Buffer.from(url.split(',')[1],'base64'));
  const rows=['colour','clay','silhouette'].map(kind=>'<div class="row">'+['left','front','top','isometric'].map(view=>'<div><img src="previews/'+m.id+'-'+kind+'-'+view+'.png"><p>'+kind+' · '+view+'</p></div>').join('')+'</div>').join('');
  await page.setContent('<meta charset="utf-8"><base href="'+base+'/"><style>body{font:18px system-ui;background:#eceef6;color:#262c57;margin:20px}.row{display:flex;gap:12px}.row>div{flex:1;background:white;min-width:0}img{width:100%}</style><h1>'+m.id+'｜實際原生四向：配色／白模／剪影</h1>'+rows);
  await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',m.id+'-review.png'),fullPage:true});
  await stage();
 }
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_review.html'));}
