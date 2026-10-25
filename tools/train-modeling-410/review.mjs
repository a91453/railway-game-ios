// Decision 410 (tools/train-shape-refresh/review.mjs's, as the native vehicle
// modelling handbook §10 asks): every group's before and after, drawn from
// the actual native vertices with one camera (the two's joint bounds), in
// colour, clay and silhouette from the side, the front, above and
// three-quarter, and small in grey as the game shows it. One sheet a group,
// OUT/review/<group>.png.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,unlinkSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');
const root=resolve(process.argv[2]),only=process.argv[3];
writeFileSync(resolve(root,'renderer.js'),readFileSync(new URL('../station-kit/renderer.js',import.meta.url).pathname,'utf8').replace('count>15000','count>200000'));
writeFileSync(resolve(root,'_review.html'),'<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.r=new NativeRenderer(document.getElementById("c"));window.ready=true;</script>');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+decodeURIComponent(new URL(q.url,'http://x').pathname));s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/opt/pw-browsers/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 const page=await browser.newPage({viewport:{width:1600,height:900}});
 const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));mkdirSync(resolve(root,'review'),{recursive:true});
 const views=['left','front','top','isometric'],kinds=[['colour',null],['clay',0xffeaeaea],['silhouette',0xff111111]];
 for(const g of [...new Set(manifest.models.map(m=>m.group))].filter(g=>!only||g===only)){
  await page.goto(base+'/_review.html');await page.waitForFunction(()=>window.ready);
  const pair=manifest.models.filter(m=>m.group===g).sort((a,b)=>a.id.endsWith('-before')?-1:b.id.endsWith('-before')?1:0);
  const shots=await page.evaluate(async({pair,views,kinds})=>{
   const buffers=[];for(const m of pair)buffers.push(await(await fetch(m.native)).arrayBuffer());
   const bounds=buffers.map(b=>{r.load(b.slice(0));return r.bounds;});
   const low=[0,1,2].map(i=>Math.min(...bounds.map(b=>b.low[i]))),high=[0,1,2].map(i=>Math.max(...bounds.map(b=>b.high[i])));
   const whole=()=>{r.centre=low.map((x,i)=>(x+high[i])/2);r.extent=low.map((x,i)=>(high[i]-x)/2);};
   const out={};
   pair.forEach((m,n)=>{const o={};
    for(const [kind,colour] of kinds){
     const buffer=buffers[n].slice(0),d=new DataView(buffer),start=16+Math.ceil(d.getUint32(12,true)/4)*4;
     if(colour!==null)for(let i=0;i<d.getUint32(8,true);i++){d.setUint32(start+i*52,0,true);for(let j=0;j<3;j++)d.setUint32(start+i*52+4+j*16+12,colour,true);}
     r.load(buffer);
     for(const view of views){whole();r.render(view,view==='front'?{width:360,height:360}:{width:900,height:view==='top'?220:300});o[kind+'-'+view]=r.png();}
     if(kind==='colour'){whole();r.render('isometric',{width:240,height:80});
      // Grey by luma, on the pixels themselves.
      const c=document.createElement('canvas');c.width=240;c.height=80;const x=c.getContext('2d');
      x.drawImage(r.canvas,0,0);const d=x.getImageData(0,0,240,80);
      for(let i=0;i<d.data.length;i+=4){const y=0.2126*d.data[i]+0.7152*d.data[i+1]+0.0722*d.data[i+2];d.data[i]=d.data[i+1]=d.data[i+2]=y;}
      x.putImageData(d,0,0);o.game=c.toDataURL();}
    }
    out[m.id]=o;});
   return out;},{pair,views,kinds});
  const cell=(src,label,style='')=>'<div><img src="'+src+'" style="'+style+'"><p>'+label+'</p></div>';
  const rows=pair.map(m=>kinds.map(([kind])=>'<div class="row"><b>'+(m.id.endsWith('-before')?'之前':'之後')+'<br>'+kind+'</b>'
   +views.map(v=>cell(shots[m.id][kind+'-'+v],v)).join('')
   +(kind==='colour'?cell(shots[m.id].game,'遊戲尺度・灰階','width:240px;height:80px'):'<div></div>')+'</div>').join('')).join('<hr>');
  await page.setContent('<meta charset="utf-8"><style>body{font:16px sans-serif;background:#eceef6;color:#262c57;margin:16px;width:1560px}.row{display:grid;grid-template-columns:70px 3fr 1.2fr 3fr 3fr 260px;gap:8px;margin-bottom:6px}.row>div{background:white;min-width:0}img{width:100%;display:block}p{margin:2px 6px;font-size:13px}</style><h2>'+g+'｜實際原生模型：配色／白模／剪影，側・正・俯・斜，同一相機</h2>'+rows);
  await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
  await page.screenshot({path:resolve(root,'review',g+'.png'),fullPage:true});
 }
}finally{await browser.close();server.close();unlinkSync(resolve(root,'_review.html'));}
console.log('ok');
