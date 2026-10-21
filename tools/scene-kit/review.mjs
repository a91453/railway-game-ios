import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,unlinkSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]||'docs/art/generated-2026-10-21-scene-kit/native3d');
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const server=createServer((req,res)=>{try{const path=resolve(root,'.'+new URL(req.url,'http://localhost').pathname);if(!path.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.png':'image/png'})[extname(path)]||'application/octet-stream');res.end(readFileSync(path));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const address='http://127.0.0.1:'+server.address().port;
let browser;
const temporary=resolve(root,'_review.html');
try {
 mkdirSync(resolve(root,'previews'),{recursive:true});
 writeFileSync(temporary,'<canvas id="canvas"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.renderer=new NativeRenderer(document.getElementById("canvas"));window.ready=true;</script>');
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1260,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(address+'/_review.html');await page.waitForFunction(()=>window.ready);
 const housing=manifest.models.filter(a=>['house','apartment','tower'].includes(a.family));
 // Additional underside oblique views expose balcony/corridor connections.
 for(const record of housing){
  const png=await page.evaluate(async a=>{renderer.load(await(await fetch(a.native)).arrayBuffer());renderer.render('isometric',{width:384,height:384,vector:[1,-1,-0.45]});return renderer.png();},record);
  writeFileSync(resolve(root,'previews',record.id+'-underside.png'),Buffer.from(png.split(',')[1],'base64'));
 }
 const style='<style>body{font:16px system-ui;color:#262c57;background:#eceef6;margin:16px}section{background:white;border-radius:10px;margin:10px 0;padding:12px}.row{display:grid;grid-template-columns:repeat(5,1fr);gap:8px}.row.housing{grid-template-columns:repeat(6,1fr)}img{width:100%;height:185px;object-fit:contain}figure{margin:0;text-align:center}h3{margin:0 0 6px}.dark{background:#262c57}.map{background:#dce9da}.night{background:#263c40}figcaption{font-size:13px}p{margin:6px}</style>';
 const figure=(path,label,cls='')=>'<figure><img class="'+cls+'" src="'+path+'"><figcaption>'+label+'</figcaption></figure>';
 const trains=manifest.models.filter(a=>['traModern','traClassic','metro','lightRail'].includes(a.family));
 const trainRows=trains.map(a=>'<section><h3>'+a.name+'</h3><div class="row">'+figure(a.views.front,'前視')+figure(a.views.back,'後視')+figure(a.views.front,'深底前視','dark')+figure(a.views.isometric,'立體')+figure(a.views.left,'側視')+'</div></section>').join('');
 async function sheet(name,title,content){await page.setContent('<meta charset="utf-8"><base href="'+address+'/">'+style+'<h1>'+title+'</h1>'+content);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));await page.screenshot({path:resolve(root,'previews',name),fullPage:true});}
 await sheet('transport-review.png','列車｜前後端、深底與側面',trainRows);
 const houseRows=housing.map(a=>'<section><h3>'+a.name+'</h3><div class="row housing">'+figure(a.views.front,'前視')+figure(a.views.right,'側視')+figure(a.views.isometric,'立體')+figure('previews/'+a.id+'-underside.png','下方斜視')+figure(a.views.isometric,'地圖淺底','map')+figure(a.views.isometric,'地圖深底','night')+'</div></section>').join('');
 await sheet('housing-review.png','住宅｜檢查騎樓窗戶、陽台樓板與支架',houseRows);
 // CSS renders actual export PNGs at review sizes; no source image edits.
 const picks=[trains[0],trains[6],housing[0],housing[3],housing[12]];
 const checks=picks.map(a=>'<section><h3>'+a.name+'</h3><div class="row">'+['','dark','map','night'].map(c=>figure(a.views.isometric,'四底色',c)).join('')+figure(a.views.front,'灰階','gray')+'</div><p>'+[120,64,44,28].map(s=>'<img src="'+a.views.isometric+'" style="width:'+s+'px;height:'+s+'px">').join('')+'<img src="'+a.views.isometric+'" style="width:120px;height:120px;filter:blur(3px)"></p></section>').join('');
 await sheet('style-review.png','四底色、小尺寸、模糊與灰階','<style>.gray{filter:grayscale(1)}</style>'+checks);
 const selected=[trains[0],trains[1],trains[6],trains[7],housing[0],housing[3]];
 const cards=selected.map(a=>'<section><h3>'+a.name+'</h3><div class="row compact">'+figure(a.views.front,'前視')+
  (a.category==='railway' ? figure(a.views.back,'後視')+figure(a.views.isometric,'立體') : figure(a.views.isometric,'立體')+figure('previews/'+a.id+'-underside.png','下方斜視'))+'</div></section>').join('');
 await sheet('fixes.png','車頭車尾與住宅接合｜修正版原生幾何','<style>main{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}main section{min-width:0;margin:0}.row.compact{grid-template-columns:repeat(3,1fr)}.compact img{height:150px}</style><main>'+cards+'</main>');
 if(errors.length)throw Error(errors.join('\n'));
 console.log('Rendered transport / housing / style review sheets and '+housing.length+' underside oblique views. Visual review is still required.');
} finally {if(browser)await browser.close();server.close();unlinkSync(temporary);}
