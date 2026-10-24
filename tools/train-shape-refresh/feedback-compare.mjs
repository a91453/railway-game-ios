// Compare two actual exported native formations with identical camera bounds.
// The actual prior delivery is preserved separately under history/.
import {createServer} from 'node:http';
import {copyFileSync,readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const current=resolve(process.argv[2]),prior=resolve(process.argv[3]);
if(!prior)throw Error('Usage: node feedback-compare.mjs CURRENT_EXPORT PRIOR_EXPORT');
const mode=process.argv[4]||'formation',electric=mode==='e200';
const id=electric?'refresh-e200':mode==='formation'?'refresh-700t-formation':'refresh-700t-'+(mode==='nose'?'cab':mode);
const family=electric?'e200':mode==='nose'?'700t-nose':mode==='cab'?'blue-cab':'700t-'+mode,label=electric?'E200 端面／輪架／屋頂修訂':'700T 風擋罩高度／車頂留白修訂';
const currentModel=JSON.parse(readFileSync(resolve(current,'manifest.json'))).models.find(m=>m.id===id);
const priorModel=JSON.parse(readFileSync(resolve(prior,'manifest.json'))).models.find(m=>m.id===id);
const before='_feedback-before.m3dmodel',after='_feedback-after.m3dmodel',html='_feedback.html';
copyFileSync(resolve(prior,priorModel.native),resolve(current,before));
copyFileSync(resolve(current,currentModel.native),resolve(current,after));
writeFileSync(resolve(current,html),'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
const server=createServer((req,res)=>{try{const p=resolve(current,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(current+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1400,height:900}}),base='http://127.0.0.1:'+server.address().port;
 await page.goto(base+'/'+html);await page.waitForFunction(()=>window.ready);
 const result=await page.evaluate(async ({paths,closeup})=>{
  let buffers=await Promise.all(paths.map(async path=>(await fetch(path)).arrayBuffer()));
  // Detail views select complete triangles from the actual delivered native
  // shell; they do not crop the PNG or change any selected vertex.
  if(closeup)buffers=buffers.map(buffer=>{
   const d=new DataView(buffer),start=16+Math.ceil(d.getUint32(12,true)/4)*4,keep=[];
   for(let i=0;i<d.getUint32(8,true);i++)if([0,1,2].every(j=>d.getFloat32(start+i*52+4+j*16,true)>=3.6999))keep.push(i);
   const out=new ArrayBuffer(start+keep.length*52),bytes=new Uint8Array(out),original=new Uint8Array(buffer);
   bytes.set(original.subarray(0,start));new DataView(out).setUint32(8,keep.length,true);
   keep.forEach((i,k)=>bytes.set(original.subarray(start+i*52,start+(i+1)*52),start+k*52));return out;
  });
  const bounds=buffers.map(b=>{renderer.load(b);return renderer.bounds;});
  const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i])));
  const centre=closeup?[8.5,0,1.9]:low.map((n,i)=>(n+high[i])/2),extent=closeup?[5.5,2,2]:low.map((n,i)=>(high[i]-n)/2),out={};
  for(const [version,buffer] of [['before',buffers[0]],['after',buffers[1]]]){
   renderer.load(buffer);renderer.centre=centre;renderer.extent=extent;
   for(const view of ['left','front','top','isometric']){renderer.render(view,{width:900,height:600});out[version+'-'+view]=renderer.png();}
  }
  return {images:out,low,high};
 },{paths:['/'+before,'/'+after],closeup:mode==='nose'});
 const entries=Object.entries(result.images);
 for(const [name,url] of entries)writeFileSync(resolve(current,'previews',family+'-'+name+'.png'),Buffer.from(url.split(',')[1],'base64'));
 const detailNote=mode==='nose'?'局部視圖選取原生模型x≥3.7的完整三角，保留原座標；不是完整車輛圖。':'';
 const cards=['left','front','top','isometric'].map(view=>`<h2>${view}｜固定公尺尺度與相機</h2><div class="row"><div><img src="previews/${family}-before-${view}.png"><p>修正前</p></div><div><img src="previews/${family}-after-${view}.png"><p>修正後</p></div></div>`).join('');
 await page.setContent('<meta charset="utf-8"><base href="'+base+'/"/><style>body{font:19px system-ui;color:#26385c;background:#eceef6;margin:24px}h1{font-size:29px}.row{display:flex;gap:16px}.row>div{background:white;border-radius:12px;padding:12px;flex:1;text-align:center}img{width:100%}p{margin:5px}</style><h1>'+label+'｜實際模型修訂前後</h1>'+cards+'<p>'+detailNote+'</p><p>兩版使用相同原生模型座標、相機中心與範圍；截圖為 Chromium WebGL 2。</p>');
 await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
 await page.screenshot({path:resolve(current,'previews',family+'-before-after.png'),fullPage:true});
 if(mode==='nose'){
  await page.setContent('<meta charset="utf-8"><base href="'+base+'/"/><style>body{font:20px system-ui;color:#26385c;background:#eceef6;margin:24px}h1{font-size:28px}.row{display:flex;gap:16px}.row>div{flex:1;background:white;border-radius:12px;padding:12px;text-align:center}img{width:100%}</style><h1>700T 風擋罩｜同相機、同公尺尺度正面對照</h1><div class="row"><div><img src="previews/'+family+'-before-front.png"><p>修正前</p></div><div><img src="previews/'+family+'-after-front.png"><p>修正後</p></div></div><p>實際原生局部模型。白車身、綠松主色帶與黑細輔線保持。</p>');
  await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
  await page.screenshot({path:resolve(current,'previews','windscreen-front-before-after.png'),fullPage:true});
 }
 console.log('Matched native-model before/after left, front and isometric views.');
}finally{if(browser)await browser.close();server.close();for(const p of [before,after,html])unlinkSync(resolve(current,p));}
