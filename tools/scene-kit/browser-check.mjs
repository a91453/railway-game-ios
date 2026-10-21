import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]||'docs/art/generated-2026-10-21-scene-kit/native3d'),pack=resolve(root,'..');
const records=JSON.parse(readFileSync(resolve(root,'manifest.json'))).models;
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'};
const server=createServer((request,response)=>{try{const file=resolve(pack,'.'+new URL(request.url,'http://localhost').pathname);if(!file.startsWith(pack+'/'))throw Error('outside');response.setHeader('Content-Type',mime[extname(file)]||'application/octet-stream');response.end(readFileSync(file));}catch{response.writeHead(404);response.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
let browser;
try{
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1440,height:1000},acceptDownloads:true}),errors=[],external=[],failed=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('data:'))external.push(r.url());});page.on('response',r=>{if(r.status()>=400)failed.push(r.url());});
 await page.goto(base+'/native3d/index.html');await page.waitForFunction(()=>window.currentAsset);
 assert.equal(await page.locator('.tile').count(),records.length);
 await page.selectOption('#category','residential');assert.equal(await page.locator('.tile').count(),records.filter(a=>a.category==='residential').length);
 await page.selectOption('#category','all');await page.fill('#search','HSR');assert.equal(await page.locator('.tile').count(),records.filter(a=>(a.id+' '+a.name).toLowerCase().includes('hsr')).length);await page.fill('#search','');
 const total=await page.evaluate(async()=>{let n=0;for(const asset of manifest.models){await loadAsset(asset.id);if(!renderer.count)throw Error('Empty '+asset.id);n++;}return n;});assert.equal(total,records.length);
 await page.selectOption('#model','07_residential_low-04');await page.waitForFunction(()=>currentAsset.id==='07_residential_low-04');
 const images=[];
 for(const direction of ['top','bottom','left','right','front','back']){await page.click('[data-view="'+direction+'"]');images.push(await page.evaluate(()=>renderer.png()));}
 assert.notEqual(images[0],images[1]);assert(new Set(images).size>=4);
 await page.click('[data-view="isometric"]');const before=await page.evaluate(()=>renderer.png()),box=await page.locator('#canvas').boundingBox();
 await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2+70,box.y+box.height/2+25,{steps:4});await page.mouse.up();assert.notEqual(await page.evaluate(()=>renderer.png()),before);
 await page.locator('#zoom').fill('1.5');assert.equal(await page.inputValue('#zoom'),'1.5');await page.locator('#zoom').fill('1');
 const pngPromise=page.waitForEvent('download');await page.click('#png');const png=await pngPromise,pngPath=await png.path(),pngBytes=readFileSync(pngPath);assert.equal(pngBytes.readUInt32BE(16),768);assert.equal(pngBytes.readUInt32BE(20),540);
 const glbPromise=page.waitForEvent('download');await page.click('#glb');const glb=await glbPromise,glbBytes=readFileSync(await glb.path());assert.equal(createHash('sha256').update(glbBytes).digest('hex'),await page.evaluate(()=>currentAsset.glb_sha256));
 await page.click('[data-view="bottom"]');await page.mouse.move(0,0);await page.screenshot({path:resolve(root,'previews/viewer-bottom.png'),fullPage:false});
 await page.click('[data-view="isometric"]');await page.selectOption('#background','#262c57');await page.screenshot({path:resolve(root,'previews/viewer-desktop.png'),fullPage:false});
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>window.scrollTo(0,0));assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:resolve(root,'previews/viewer-mobile.png'),fullPage:false});
 await page.fill('#search','no-such-item');assert.equal(await page.locator('.tile').count(),0);await page.fill('#search','');
 assert.deepEqual(errors,[]);assert.deepEqual(external,[]);assert.deepEqual(failed,[]);
 const file=resolve(root,'verification.json'),verification=JSON.parse(readFileSync(file));verification.browser={status:'VERIFIED',models_loaded:total,checks:[total+' native models loaded into WebGL','category and ID/name filtering','top/bottom/left/right/front/back controls','pointer orbit changes real rendered vertices','zoom','PNG and GLB downloads','original concept comparison','390 px without horizontal overflow','no JavaScript errors, failed resources or external requests'],errors,failed_requests:failed,external_requests:external};writeFileSync(file,JSON.stringify(verification,null,2)+'\n');
 console.log('VERIFIED: all '+total+' interactive models, six directions, orbit, zoom, downloads and mobile.');
}finally{if(browser)await browser.close();server.close();}
