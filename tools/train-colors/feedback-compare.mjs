import {createServer} from 'node:http';
import {readFileSync,writeFileSync,copyFileSync,unlinkSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]),prior=resolve(process.argv[3]);
const trains=[['tram','green-tram-formation','低地板電車 · 綠松'],['commuter','green-commuter-formation','雙節通勤車 · 霧藍'],['urban','urban-three-formation','三節都市車 · 柔綠']];
for(const [family,id] of trains)copyFileSync(resolve(prior,'models',id+'.m3dmodel'),resolve(root,'_before-'+family+'.m3dmodel'));
writeFileSync(resolve(root,'_feedback.html'),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1400,height:900}}),base='http://127.0.0.1:'+server.address().port;
 await page.goto(base+'/_feedback.html');await page.waitForFunction(()=>window.ready);
 const images=await page.evaluate(async trains=>{
  const buffers=await Promise.all(trains.flatMap(([family,id])=>['_before-'+family+'.m3dmodel','models/'+id+'.m3dmodel']).map(async p=>(await fetch(p)).arrayBuffer()));
  const bounds=buffers.map(b=>{renderer.load(b);return renderer.bounds;});
  const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i]))),out={};
  for(let i=0;i<trains.length;i++)for(let version=0;version<2;version++){
   renderer.load(buffers[i*2+version]);renderer.centre=low.map((v,j)=>(v+high[j])/2);renderer.extent=low.map((v,j)=>(high[j]-v)/2);
   for(const view of ['left','front','isometric']){renderer.render(view,{width:900,height:view==='left'?260:600});out[(version?'after-':'before-')+trains[i][0]+'-'+view]=renderer.png();}
  }
  return out;
 },trains);
 for(const [name,url] of Object.entries(images))writeFileSync(resolve(root,'previews',name+'.png'),Buffer.from(url.split(',')[1],'base64'));
 const style='<style>body{font:19px system-ui;color:#26385c;background:#eceef6;margin:24px}h1{font-size:29px}.row{display:flex;gap:16px}.row>div{background:white;border-radius:12px;padding:12px;flex:1;min-width:0;text-align:center}img{width:100%}p{margin:5px}</style>';
 function row(family,view){return '<div class="row">'+['before','after'].map(v=>'<div><img src="previews/'+v+'-'+family+'-'+view+'.png"><p>'+(v==='before'?'修正前':'修正後')+'</p></div>').join('')+'</div>';}
 async function sheet(file,title,body){await page.setContent('<meta charset="utf-8"><base href="'+base+'/">'+style+'<h1>'+title+'</h1>'+body+'<p>實際原生模型，同一公尺座標、相機中心與範圍；只有配色改動。</p>');await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',file),fullPage:true});}
 for(const [family,,title] of trains)await sheet('before-after-'+family+'.png',title+'｜配色前後',['left','front','isometric'].map(v=>'<h2>'+v+'</h2>'+row(family,v)).join(''));
 await sheet('before-after.png','三台列車｜同尺度、同相機配色前後',trains.map(([family,,title])=>'<h2>'+title+'</h2>'+row(family,'isometric')).join(''));
 console.log('Rendered all three native before/after pairs in matched left, front and isometric cameras.');
}finally{if(browser)await browser.close();server.close();for(const [family] of trains)unlinkSync(resolve(root,'_before-'+family+'.m3dmodel'));unlinkSync(resolve(root,'_feedback.html'));}
