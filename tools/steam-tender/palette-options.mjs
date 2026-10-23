// Colour alternatives only; geometry is the final native formation throughout.
import{createServer}from'node:http';import{readFileSync,writeFileSync,unlinkSync}from'node:fs';import{resolve,extname}from'node:path';import{createRequire}from'node:module';
const{chromium}=createRequire(import.meta.url)('playwright'),root=resolve(process.argv[2]);
writeFileSync(resolve(root,'_options.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',extname(p)==='.js'?'text/javascript':extname(p)==='.png'?'image/png':'text/html');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});const page=await browser.newPage({viewport:{width:1300,height:900}}),base='http://127.0.0.1:'+server.address().port;await page.goto(base+'/_options.html');await page.waitForFunction(()=>window.ready);
 const results=await page.evaluate(async()=>{const original=await(await fetch('models/steam-formation.m3dmodel')).arrayBuffer(),out={};
 for(const[name,rgb]of [['chosen-teal',null],['alternative-ivory',[242,240,234]],['alternative-blue',[74,114,168]]]){const buffer=original.slice(0),d=new DataView(buffer),start=16+Math.ceil(d.getUint32(12,true)/4)*4;
  if(rgb)for(let i=0;i<d.getUint32(8,true);i++)for(let j=0;j<3;j++){const p=start+i*52+4+j*16+12,c=d.getUint32(p,true),r=c&255,g=(c>>>8)&255,b=(c>>>16)&255;if(g===b&&g>r+15){const f=g/140,channels=rgb.map(x=>Math.min(255,Math.round(x*f)));d.setUint32(p,(0xff000000|channels[0]|channels[1]<<8|channels[2]<<16)>>>0,true);}}
  renderer.load(buffer);renderer.render('isometric',{width:1200,height:430});out[name]=renderer.png();
 }return out;});
 for(const[name,url]of Object.entries(results))writeFileSync(resolve(root,'previews','palette-'+name+'.png'),Buffer.from(url.split(',')[1],'base64'));
 await page.setContent('<meta charset="utf-8"><base href="'+base+'/"><style>body{font:18px system-ui;background:#eceef6;color:#262c57}img{width:100%;max-height:430px;object-fit:contain}div{background:white;margin:12px;padding:12px}</style><h1>配色比較｜同一最終幾何與相機</h1>'+Object.keys(results).map((name,i)=>'<div><img src="previews/palette-'+name+'.png"><p>'+['採用：霧綠／石墨／金砂','未採用：暖白／石墨／金砂（與前批白車太接近）','未採用：霧藍／石墨／金砂（輪組與車身層次較弱）'][i]+'</p></div>').join(''));
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews/palette-options.png'),fullPage:true});
}finally{if(browser)await browser.close();server.close();unlinkSync(resolve(root,'_options.html'));}
