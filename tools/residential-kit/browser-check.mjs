import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)('playwright'),root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const server=createServer((req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname;if(name==='/favicon.ico'){res.writeHead(204);res.end();return;}const p=resolve(root,'.'+decodeURIComponent(name));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
let browser;
try {
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1440,height:1000},acceptDownloads:true}),errors=[],failed=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)failed.push(r.url());});page.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('data:'))external.push(r.url());});
 await page.goto(base+'/index.html');await page.waitForFunction(()=>window.currentAsset);
 assert.equal(await page.locator('.tile').count(),manifest.model_count);
 for(const c of ['home','boundary','yard']){await page.selectOption('#category',c);assert.equal(await page.locator('.tile').count(),8);}
 await page.selectOption('#category','example');assert.equal(await page.locator('.tile').count(),4);
 await page.selectOption('#category','all');await page.fill('#search','屋頂水塔');assert.equal(await page.locator('.tile').count(),1);await page.fill('#search','');
 const total=await page.evaluate(async()=>{let n=0;for(const m of manifest.models){await loadAsset(m.id);if(!renderer.count)throw Error('Empty '+m.id);n++;}return n;});assert.equal(total,manifest.model_count);
 const decoded=await page.evaluate(async()=>{
  const canvas=document.createElement('canvas');canvas.width=384;canvas.height=384;const ctx=canvas.getContext('2d',{willReadFrequently:true});let count=0;
  for(const asset of manifest.models)for(const view of manifest.directions){
   const response=await fetch(asset.views[view]);if(!response.ok)throw Error('Missing '+asset.views[view]);
   const image=await createImageBitmap(await response.blob());if(image.width!==384||image.height!==384)throw Error('Invalid PNG '+asset.id+' '+view);
   ctx.clearRect(0,0,384,384);ctx.drawImage(image,0,0);image.close();
   const pixels=ctx.getImageData(0,0,384,384).data;let visible=0,left=384,top=384,right=0,bottom=0;
   for(let y=0;y<384;y++)for(let x=0;x<384;x++)if(pixels[(y*384+x)*4+3]>16){visible++;left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);}
   if(visible<20||left<2||top<2||right>381||bottom>381)throw Error('Empty/clipped PNG '+asset.id+' '+view);
   count++;
  }return count;
 });assert.equal(decoded,manifest.model_count*7);
 await page.evaluate(()=>loadAsset('residential-example-laneStreet'));
 const images=[];for(const view of ['top','bottom','left','right','front','back']){await page.click('[data-view="'+view+'"]');images.push(await page.evaluate(()=>renderer.png()));}assert(new Set(images).size>=5);
 await page.click('[data-view="isometric"]');const before=await page.evaluate(()=>renderer.png()),box=await page.locator('#canvas').boundingBox();
 await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2+90,box.y+box.height/2+35,{steps:5});await page.mouse.up();assert.notEqual(await page.evaluate(()=>renderer.png()),before);
 await page.locator('#zoom').fill('1.5');assert.equal(await page.inputValue('#zoom'),'1.5');await page.locator('#zoom').fill('1');
 let pending=page.waitForEvent('download');await page.click('#png');let download=await pending;assert.equal(readFileSync(await download.path()).readUInt32BE(16),900);
 pending=page.waitForEvent('download');await page.click('#glb');download=await pending;assert.equal(createHash('sha256').update(readFileSync(await download.path())).digest('hex'),await page.evaluate(()=>currentAsset.glb_sha256));
 pending=page.waitForEvent('download');await page.click('#native');download=await pending;assert.equal(createHash('sha256').update(readFileSync(await download.path())).digest('hex'),await page.evaluate(()=>currentAsset.native_sha256));
 await page.click('[data-view="isometric"]');await page.mouse.move(0,0);await page.screenshot({path:resolve(root,'previews/viewer-desktop.png'),fullPage:false});
 await page.evaluate(()=>loadAsset('residential-balconyModule'));await page.click('[data-view="bottom"]');await page.screenshot({path:resolve(root,'previews/viewer-underside.png'),fullPage:false});
 await page.click('[data-view="isometric"]');await page.setViewportSize({width:390,height:844});await page.evaluate(()=>window.scrollTo(0,0));assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:resolve(root,'previews/viewer-mobile.png'),fullPage:false});
 assert.deepEqual(errors,[]);assert.deepEqual(failed,[]);assert.deepEqual(external,[]);
 const path=resolve(root,'verification.json'),result=JSON.parse(readFileSync(path));result.browser={status:'VERIFIED',models_loaded:total,images_fully_decoded:decoded,checks:['three categories / examples / Chinese name filtering','seven directions','full RGBA decode, nonempty and unclipped bounds for every PNG','pointer orbit changes rendered geometry','zoom','PNG / native / GLB download hashes','390 px without horizontal overflow','no external requests / missing resources / JavaScript errors']};writeFileSync(path,JSON.stringify(result,null,2)+'\n');
 console.log('VERIFIED browser: '+total+' models, '+decoded+' decoded PNGs, filters, directions, orbit, zoom, downloads and mobile.');
}finally{if(browser)await browser.close();server.close();}
